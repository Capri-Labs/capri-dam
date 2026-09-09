# frozen_string_literal: true

require "rails_helper"

RSpec.describe Observability::Report do
  subject(:report) { described_class.call }

  describe "structure" do
    it "returns every section the dashboard renders" do
      expect(report.keys).to include(
        :generated_at, :app_server, :database, :cache_queue, :storage_backend,
        :runtime, :queues, :redis, :content_pipeline, :preservation
      )
    end

    it "keeps the original card keys so an older client does not break" do
      expect(report[:app_server]).to include(:status, :ruby_version, :rails_version)
      expect(report[:cache_queue]).to include(:status, :queue_depth, :active_workers)
    end
  end

  describe "failure isolation" do
    # A diagnostics page that goes blank because one subsystem is unreachable
    # fails at the exact moment it is needed.
    it "reports a failing section without taking the rest of the page down" do
      allow(Fixity::Sampler).to receive(:coverage).and_raise(PG::ConnectionBad, "boom")

      expect(report[:preservation]).to include(status: "error", error: a_string_including("boom"))
      expect(report[:content_pipeline][:status]).not_to eq("error")
      expect(report[:runtime][:status]).to eq("healthy")
    end
  end

  describe "database" do
    it "probes with a real query rather than asking whether a connection exists" do
      # `connection.active?` answers "have we connected?", not "does the
      # database respond?" — it is false on an untouched lazy connection and
      # true on one whose socket died ten minutes ago.
      expect(report[:database][:status]).to eq("healthy")
      expect(report[:database][:latency_ms]).to be_a(Numeric)
    end

    it "reports pool pressure, which is invisible from the database side" do
      section = report[:database]

      expect(section[:pool_size]).to be_positive
      expect(section[:pool_utilisation_percent]).to be_between(0, 100)
      expect(section).to have_key(:waiting)
    end

    it "reports the database size and the longest running query" do
      expect(report[:database][:size_bytes]).to be_positive
      expect(report[:database][:longest_query_seconds]).to be >= 0
    end
  end

  describe "runtime" do
    it "reports the node that answered the request" do
      section = report[:runtime]

      expect(section[:hostname]).to be_present
      expect(section[:pid]).to eq(Process.pid)
      expect(section[:heap_live_objects]).to be_positive
    end

    it "derives uptime from the recorded boot time" do
      allow(Rails.application.config.x).to receive(:booted_at).and_return(90.seconds.ago)

      expect(report[:runtime][:uptime_seconds]).to be_within(5).of(90)
    end

    it "reports a nil uptime rather than a wrong one when boot time is unknown" do
      allow(Rails.application.config.x).to receive(:booted_at).and_return(nil)

      expect(report[:runtime][:uptime_seconds]).to be_nil
    end
  end

  describe "queues" do
    before do
      allow(Sidekiq::Queue).to receive(:all).and_return([
        instance_double(Sidekiq::Queue, name: "default", size: 0, latency: 0.0, paused?: false),
        instance_double(Sidekiq::Queue, name: "ingest", size: 4, latency: 900.0, paused?: false),
      ])
    end

    # A queue 10,000 deep that drains in seconds is fine; one three deep that
    # has not moved in an hour is not.
    it "grades a queue on latency, not depth" do
      rows = report[:queues][:queues]

      expect(rows.find { |q| q[:name] == "ingest" }[:status]).to eq("degraded")
      expect(rows.find { |q| q[:name] == "default" }[:status]).to eq("healthy")
    end

    it "sorts the worst queue to the top" do
      expect(report[:queues][:queues].first[:name]).to eq("ingest")
    end

    it "marks the whole section degraded when any queue is" do
      expect(report[:queues][:status]).to eq("degraded")
    end

    it "surfaces the retry and dead sets that an enqueued total hides" do
      expect(report[:queues]).to include(:retry_size, :scheduled_size, :dead_size)
    end
  end

  describe "content_pipeline" do
    let!(:ready)   { create(:asset, status: "ready") }
    let!(:deleted) { create(:asset, deleted_at: 2.days.ago) }

    it "counts only live assets, and reports the bin separately" do
      section = report[:content_pipeline]

      expect(section[:by_status]["ready"]).to eq(1)
      expect(section[:total_assets]).to eq(1)
      expect(section[:in_bin]).to eq(1)
    end

    # Nothing is working on these — a worker died and left them behind, and no
    # other number on the page would show it.
    it "counts an asset left in processing as stuck, not as in progress" do
      create(:asset, status: "processing").update_columns(updated_at: 3.hours.ago)

      expect(report[:content_pipeline][:stuck_processing]).to eq(1)
      expect(report[:content_pipeline][:status]).to eq("degraded")
    end

    it "does not call an asset that started processing a moment ago stuck" do
      create(:asset, status: "processing")

      expect(report[:content_pipeline][:stuck_processing]).to eq(0)
    end

    it "treats a failed asset as a degraded pipeline" do
      create(:asset, status: "failed")

      expect(report[:content_pipeline][:status]).to eq("degraded")
    end
  end

  describe "preservation" do
    let(:asset) { create(:asset) }
    let(:version) { asset.asset_versions.first || create(:asset_version, asset: asset) }

    it "reports coverage as the headline figure" do
      expect(report[:preservation]).to include(:coverage_percent, :verifiable, :unverifiable, :due_now)
    end

    # A library that has simply not been swept yet has not lost anything.
    it "calls thin coverage degraded, not failing" do
      allow(Fixity::Sampler).to receive(:coverage).and_return(coverage(percent: 0))

      expect(report[:preservation][:status]).to eq("degraded")
    end

    it "escalates only when a check actually found corruption" do
      allow(Fixity::Sampler).to receive(:coverage).and_return(coverage(percent: 100))
      FixityCheck.create!(asset: asset, asset_version: version, status: "failed", checked_at: 1.day.ago)

      expect(report[:preservation][:status]).to eq("offline")
      expect(report[:preservation][:failing_last_30d]).to eq(1)
    end

    it "does not raise an old failure that has since aged out of the window" do
      allow(Fixity::Sampler).to receive(:coverage).and_return(coverage(percent: 100))
      FixityCheck.create!(asset: asset, asset_version: version, status: "failed", checked_at: 90.days.ago)

      expect(report[:preservation][:status]).to eq("healthy")
    end

    def coverage(percent:)
      {
        coverage_percent: percent, verifiable: 10, unverifiable: 0,
        never_checked: 0, due_now: 0, oldest_check_at: nil, by_status: {}
      }
    end
  end
end
