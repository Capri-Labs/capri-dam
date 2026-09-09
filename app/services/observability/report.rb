# frozen_string_literal: true

module Observability
  # The single diagnostic payload behind the "System Observability" tab.
  #
  # == Why this exists as a service
  #
  # The tab previously answered one question — "is each dependency up?" — with
  # four green ticks. That is close to the least useful thing an operator can
  # be told, because by the time Postgres or Redis is *down* they already know.
  # The questions actually asked during an incident are narrower: which queue
  # is backing up, how close the connection pool is to exhaustion, whether
  # assets are piling up in `processing`, and when the stored bytes were last
  # proven intact. Each of those needs a number, not a tick.
  #
  # == Failure isolation
  #
  # Every section is computed behind {#section}, which rescues and returns a
  # +status: "error"+ stub. A diagnostics page that goes blank because one
  # subsystem is unreachable fails at the exact moment it is needed — the
  # unreachable subsystem is usually the thing being investigated.
  #
  # == Cost
  #
  # This runs on demand from an admin screen, not per request. It is still kept
  # to counts, aggregates and metadata reads; nothing here loads a row set.
  class Report
    # Assets sitting in `processing` for longer than this are almost certainly
    # not processing — a worker died mid-job and nothing marked them failed.
    STUCK_PROCESSING_AFTER = 1.hour

    # Sidekiq's own definition of an unhealthy queue is latency, not depth: a
    # queue 10,000 deep that drains in seconds is fine, and one 3 deep that has
    # not moved in an hour is not.
    QUEUE_LATENCY_WARNING = 60 # seconds

    # Below this, the library has not been swept enough to make any claim about
    # its own integrity.
    COVERAGE_WARNING_PERCENT = 50

    def self.call
      new.call
    end

    def call
      {
        generated_at: Time.current,
        # Retained under their original keys: the tab's existing status cards
        # read these, and older clients must not break.
        app_server: section { app_server },
        database: section { database },
        cache_queue: section { cache_queue },
        storage_backend: section { storage_backend },
        # Added detail.
        runtime: section { runtime },
        queues: section { queues },
        redis: section { redis },
        content_pipeline: section { content_pipeline },
        preservation: section { preservation },
      }
    end

    private

    # Runs a section, converting any failure into a reportable state rather
    # than letting it take the whole page down.
    def section
      yield
    rescue StandardError => e
      { status: "error", error: e.message }
    end

    # -- Sections ------------------------------------------------------------

    def app_server
      {
        status: "healthy",
        environment: Rails.env,
        rails_version: Rails.version,
        ruby_version: RUBY_VERSION,
        uptime: host_uptime,
      }
    end

    # Process-level facts. Distinct from +app_server+ because in a multi-node
    # deployment these describe *the node that answered this request*, which is
    # exactly what you need when only some requests are misbehaving.
    def runtime
      booted_at = Rails.application.config.x.booted_at

      {
        status: "healthy",
        hostname: Socket.gethostname,
        pid: Process.pid,
        booted_at: booted_at,
        uptime_seconds: booted_at ? (Time.current - booted_at).round : nil,
        revision: revision,
        time_zone: Time.zone.name,
        # A steadily climbing heap between refreshes is the cheapest available
        # signal of a leak, and needs no external APM to read.
        heap_live_objects: GC.stat(:heap_live_slots),
        gc_major_count: GC.stat(:major_gc_count),
        threads: Thread.list.size,
      }
    end

    def database
      pool = ActiveRecord::Base.connection_pool
      stat = pool.stat

      started = monotonic
      # A real round-trip, not `connection.active?`. Connections are lazy, so
      # `active?` reports false on an untouched connection and true on one
      # whose socket died ten minutes ago — it answers "have we connected?",
      # not "does the database respond?", and only the second is a health
      # check. Timing it also makes latency_ms mean something.
      ActiveRecord::Base.connection.select_value("SELECT 1")
      latency = elapsed_ms(started)
      connected = true

      {
        status: connected ? "healthy" : "offline",
        latency_ms: latency,
        adapter: ActiveRecord::Base.connection.adapter_name,
        server_version: server_version,
        pool_size: pool.size,
        active_connections: stat[:busy],
        idle_connections: stat[:idle],
        # The number that predicts an outage. A pool at 100% queues requests
        # inside the app, where no database-side metric will ever show it.
        pool_utilisation_percent: percentage(stat[:busy], pool.size),
        waiting: stat[:waiting],
        size_bytes: database_size_bytes,
        longest_query_seconds: longest_running_query_seconds,
      }
    end

    # Kept for the existing summary card. Detail now lives in {#queues} and
    # {#redis}.
    def cache_queue
      stats = sidekiq_stats
      started = monotonic
      Sidekiq.redis { |conn| conn.call("PING") }

      {
        status: "healthy",
        latency_ms: elapsed_ms(started),
        redis_version: redis_info["redis_version"] || "Unknown",
        queue_depth: stats.enqueued,
        processed: stats.processed,
        failed: stats.failed,
        active_workers: Sidekiq::Workers.new.size,
        processes: Sidekiq::ProcessSet.new.size,
      }
    rescue StandardError => e
      { status: "degraded", error: "Sidekiq/Redis offline. Details: #{e.message}" }
    end

    # Per-queue depth *and* latency, plus the three sets a single "enqueued"
    # total hides completely. A growing retry set and a non-empty dead set are
    # both invisible under the old aggregate.
    def queues
      stats = sidekiq_stats

      queue_rows = Sidekiq::Queue.all.map do |queue|
        latency = queue.latency.round(1)
        {
          name: queue.name,
          size: queue.size,
          latency_seconds: latency,
          paused: queue.paused?,
          status: latency > QUEUE_LATENCY_WARNING ? "degraded" : "healthy",
        }
      end.sort_by { |q| -q[:latency_seconds] }

      {
        status: queue_rows.any? { |q| q[:status] == "degraded" } ? "degraded" : "healthy",
        queues: queue_rows,
        retry_size: Sidekiq::RetrySet.new.size,
        scheduled_size: Sidekiq::ScheduledSet.new.size,
        # Jobs that exhausted every retry. Nothing will pick these up again;
        # they are lost work until somebody looks at them.
        dead_size: Sidekiq::DeadSet.new.size,
        processed: stats.processed,
        failed: stats.failed,
        busy: Sidekiq::Workers.new.size,
        processes: sidekiq_processes,
      }
    end

    def redis
      info = redis_info
      raise "Redis unreachable" if info.empty?

      hits = info["keyspace_hits"].to_i
      misses = info["keyspace_misses"].to_i

      {
        status: "healthy",
        version: info["redis_version"],
        used_memory: info["used_memory_human"],
        used_memory_peak: info["used_memory_peak_human"],
        # Non-zero eviction on a Redis holding the job queues means Sidekiq
        # work has been silently discarded, not delayed.
        evicted_keys: info["evicted_keys"].to_i,
        connected_clients: info["connected_clients"].to_i,
        uptime_days: info["uptime_in_days"].to_i,
        hit_rate_percent: percentage(hits, hits + misses),
      }
    end

    def storage_backend
      service = ActiveStorage::Blob.service
      test_key = "healthcheck-#{SecureRandom.uuid}.txt"

      started = monotonic
      service.upload(test_key, StringIO.new("1"))
      service.download(test_key)
      service.delete(test_key)

      {
        status: "healthy",
        provider: service.class.name.demodulize,
        latency_ms: elapsed_ms(started),
        blob_count: ActiveStorage::Blob.count,
        stored_bytes: ActiveStorage::Blob.sum(:byte_size),
      }
    rescue StandardError => e
      { status: "unreachable", error: "Storage driver error: #{e.message}" }
    end

    # Whether the product itself is healthy, as opposed to its infrastructure.
    # Every dependency can be green while ingestion is quietly broken.
    def content_pipeline
      active = Asset.where(deleted_at: nil)
      by_status = active.group(:status).count
      stuck = active.where(status: "processing")
                    .where(updated_at: ...STUCK_PROCESSING_AFTER.ago)
                    .count
      failed = by_status["failed"].to_i

      {
        status: pipeline_status(stuck, failed),
        total_assets: by_status.values.sum,
        by_status: by_status,
        # Not "in progress" — nothing is working on these. A worker died and
        # left them, and no other number on this page would show it.
        stuck_processing: stuck,
        ingested_last_24h: active.where(created_at: 24.hours.ago..).count,
        in_bin: Asset.where.not(deleted_at: nil).count,
        quarantined: QuarantinedAsset.count,
      }
    end

    # Surfaces the fixity record that until now was only readable through the
    # API. The headline is coverage: the proportion of holdings with *any*
    # recent evidence behind them.
    def preservation
      coverage = Fixity::Sampler.coverage
      formats = Preservation::FormatRegistry.profile.fetch(:totals, {})
      failing = FixityCheck.failing.where(checked_at: 30.days.ago..).count

      {
        status: preservation_status(coverage, failing),
        coverage_percent: coverage[:coverage_percent],
        verifiable: coverage[:verifiable],
        # Ingested without a checksum, so they can never be proven intact.
        # A coverage gap, not a failure.
        unverifiable: coverage[:unverifiable],
        never_checked: coverage[:never_checked],
        due_now: coverage[:due_now],
        oldest_check_at: coverage[:oldest_check_at],
        last_run_at: FixityCheck.maximum(:checked_at),
        checks_last_24h: FixityCheck.where(checked_at: 24.hours.ago..).count,
        failing_last_30d: failing,
        by_status: coverage[:by_status],
        high_risk_formats: formats[:high_risk].to_i,
        medium_risk_formats: formats[:medium_risk].to_i,
        distinct_formats: formats[:distinct_formats].to_i,
      }
    end

    # -- Helpers -------------------------------------------------------------

    def pipeline_status(stuck, failed)
      return "degraded" if stuck.positive? || failed.positive?

      "healthy"
    end

    # Corruption is unambiguous; thin coverage is only a warning. They are kept
    # apart so a library that simply has not been swept yet does not present as
    # a library that has lost data.
    def preservation_status(coverage, failing)
      return "offline" if failing.positive?
      return "degraded" if coverage[:coverage_percent].to_f < COVERAGE_WARNING_PERCENT

      "healthy"
    end

    def sidekiq_stats
      require "sidekiq/api"
      Sidekiq::Stats.new
    end

    def sidekiq_processes
      Sidekiq::ProcessSet.new.map do |process|
        {
          hostname: process["hostname"],
          pid: process["pid"],
          concurrency: process["concurrency"],
          busy: process["busy"],
          queues: Array(process["queues"]),
        }
      end
    end

    def redis_info
      @redis_info ||= (Sidekiq.redis { |conn| conn.info } || {})
    rescue StandardError
      @redis_info = {}
    end

    def server_version
      ActiveRecord::Base.connection.select_value("SHOW server_version").to_s.split.first
    rescue StandardError
      nil
    end

    def database_size_bytes
      ActiveRecord::Base.connection.select_value("SELECT pg_database_size(current_database())").to_i
    rescue StandardError
      nil
    end

    # The age of the oldest query still running. One long transaction is what
    # blocks migrations and holds vacuum back, and it is invisible in every
    # other number here.
    def longest_running_query_seconds
      ActiveRecord::Base.connection.select_value(<<~SQL.squish).to_f.round(1)
        SELECT COALESCE(MAX(EXTRACT(EPOCH FROM (NOW() - query_start))), 0)
        FROM pg_stat_activity
        WHERE state = 'active' AND query NOT ILIKE '%pg_stat_activity%'
      SQL
    rescue StandardError
      nil
    end

    def host_uptime
      `uptime`.strip
    rescue StandardError
      "Unavailable"
    end

    def revision
      ENV["GIT_SHA"].presence || read_revision_file
    end

    def read_revision_file
      path = Rails.root.join("REVISION")
      File.read(path).strip.first(12) if File.exist?(path)
    rescue StandardError
      nil
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started)
      ((monotonic - started) * 1000).round(2)
    end

    def percentage(part, total)
      return 0.0 if total.to_i.zero?

      ((part.to_f / total) * 100).round(1)
    end
  end
end
