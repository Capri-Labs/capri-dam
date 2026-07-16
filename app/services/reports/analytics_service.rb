module Reports
  # AnalyticsService — powers the live dashboard charts.
  #
  # Design principles:
  # - Every query uses SQL aggregates (COUNT, SUM, GROUP BY) — never full scans
  # - Result sets are capped (LIMIT) to protect the query planner
  # - AI insights are threshold-based anomaly detection — no LLM call required
  # - Cached per date_from + folder filter key for 5 minutes to survive polling spikes
  class AnalyticsService
    CACHE_TTL = 5.minutes

    # @param range_key [String] one of the preset date range keys (see
    #   +compute_date_from+), or "custom" when +custom_from+/+custom_to+ are given.
    # @param custom_from [Time, nil]
    # @param custom_to [Time, nil]
    # @param folder_ids [Array<String>, String, nil] one or more folder ids to
    #   scope every metric to. Automatically expanded to include descendant
    #   folders (selecting a parent folder implicitly includes its subtree).
    #   +nil+/blank means "all folders" (no filter).
    def initialize(range_key = "last_30_days", custom_from: nil, custom_to: nil, folder_ids: nil)
      @range_key   = range_key
      @date_from   = custom_from || compute_date_from(range_key)
      @date_to     = custom_to   || Time.current
      @folder_ids  = folder_ids.present? ? Folder.expand_ids_with_descendants(Array(folder_ids)) : nil
    end

    def call
      cache_key = "reports_analytics:#{@range_key}:#{@date_from.to_date}:#{folder_cache_key}"

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        {
          stats:       stats,
          time_series: time_series,
          breakdowns:  breakdowns,
          ai_insights: ai_insights,
          folder_filter: folder_filter_summary,
        }
      end
    end

    private

    # ─── Stats (single aggregate query each) ─────────────────────────────────

    def stats
      # NOTE: `:from` here used to be a *named bind placeholder* embedded
      # inside a raw `.select(...)` fragment — ActiveRecord only substitutes
      # named binds supplied to `.where(...)`, never inside `.select`, so a
      # bogus `.where("1=1")` never bound it. Every request hit a Postgres
      # syntax error, silently swallowed by the rescue below, leaving the
      # entire stats block (and therefore every KPI card on the Reports page)
      # blank. Fixed by safely interpolating the already-validated
      # `@date_from` Time value via `connection.quote`.
      from_sql = ActiveRecord::Base.connection.quote(@date_from)

      asset_scope = @folder_ids.present? ? Asset.unscoped.where(folder_id: @folder_ids) : Asset.unscoped

      asset_counts  = asset_scope.select(
        "COUNT(*) FILTER (WHERE deleted_at IS NULL)                              AS total_assets",
        "COUNT(*) FILTER (WHERE status = 'ready'   AND deleted_at IS NULL)       AS active_assets",
        "COUNT(*) FILTER (WHERE status = 'pending' AND deleted_at IS NULL)       AS pending_assets",
        "COUNT(*) FILTER (WHERE created_at >= #{from_sql} AND deleted_at IS NULL) AS new_in_range",
        "COUNT(*) FILTER (WHERE deleted_at IS NOT NULL)                          AS in_trash"
      ).limit(1).to_a.first
                            .attributes.transform_values(&:to_i)

      workflow_scope = @folder_ids.present? ? WorkflowInstance.joins(:asset).where(assets: { folder_id: @folder_ids }) : WorkflowInstance

      # Columns are qualified with `workflow_instances.` since the folder
      # filter above joins in `assets`, which also has a `status` column —
      # without qualification Postgres raises "column reference is ambiguous".
      workflow_counts = workflow_scope.select(
        "COUNT(*) FILTER (WHERE workflow_instances.status IN ('pending','in_progress'))             AS active_workflows",
        "COUNT(*) FILTER (WHERE workflow_instances.status = 'pending')                              AS pending_approvals",
        "COUNT(*) FILTER (WHERE workflow_instances.status = 'approved' AND workflow_instances.updated_at >= #{from_sql}) AS approved_in_range",
        "COUNT(*) FILTER (WHERE workflow_instances.status = 'rejected' AND workflow_instances.updated_at >= #{from_sql}) AS rejected_in_range",
        "ROUND(AVG(EXTRACT(EPOCH FROM (workflow_instances.completed_at - workflow_instances.started_at))/3600)::numeric, 1) AS avg_approval_hours"
      ).limit(1).to_a.first&.attributes&.except("id") || {}

      embedding_scope = @folder_ids.present? ? AssetEmbedding.joins(:asset).where(assets: { folder_id: @folder_ids }) : AssetEmbedding

      embedding_counts = embedding_scope.select(
        "COUNT(*) AS with_embedding"
      ).limit(1).to_a.first&.attributes || {}

      duplicate_scope = @folder_ids.present? ? IngestionBatch.where(destination_folder_id: @folder_ids) : IngestionBatch
      duplicate_count = duplicate_scope.sum(:duplicate_count).to_i

      storage_gb = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT ROUND(COALESCE(SUM((properties->>'size')::bigint),0)::numeric / 1073741824, 2) " \
          "FROM assets WHERE deleted_at IS NULL AND properties->>'size' IS NOT NULL#{folder_sql_clause}",
        ])
      ).to_f

      ai_total    = asset_counts["total_assets"].to_i
      ai_covered  = embedding_counts["with_embedding"].to_i
      ai_coverage = ai_total > 0 ? (ai_covered.to_f / ai_total * 100).round(1) : 0

      {
        total_assets:             asset_counts["total_assets"],
        active_assets:            asset_counts["active_assets"],
        pending_assets:           asset_counts["pending_assets"],
        new_in_range:             asset_counts["new_in_range"],
        in_trash:                 asset_counts["in_trash"],
        active_workflows:         workflow_counts["active_workflows"].to_i,
        pending_approvals:        workflow_counts["pending_approvals"].to_i,
        approved_in_range:        workflow_counts["approved_in_range"].to_i,
        rejected_in_range:        workflow_counts["rejected_in_range"].to_i,
        avg_approval_hours:       workflow_counts["avg_approval_hours"].to_f,
        storage_used_gb:          storage_gb,
        ai_embedding_coverage_pct: ai_coverage,
        ai_assets_covered:        ai_covered,
        duplicates_blocked:       duplicate_count,
        range_label:              range_label,
      }
    rescue => e
      Rails.logger.error("[AnalyticsService] stats failed: #{e.message}")
      {}
    end

    # ─── Time Series (GROUP BY date) ─────────────────────────────────────────

    def time_series
      # Assets created per day in range
      assets_by_day = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT DATE(created_at) AS date, COUNT(*) AS count
           FROM assets
           WHERE created_at >= ? AND deleted_at IS NULL#{folder_sql_clause}
           GROUP BY DATE(created_at)
           ORDER BY date",
          @date_from,
        ])
      ).map { |r| { date: r["date"].to_s, count: r["count"].to_i } }

      # Workflows completed per day
      workflows_by_day = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT DATE(wi.completed_at) AS date, COUNT(*) AS count
           FROM workflow_instances wi
           JOIN assets a ON a.id = wi.asset_id
           WHERE wi.completed_at >= ? AND wi.status = 'approved'#{folder_sql_clause("a.folder_id")}
           GROUP BY DATE(wi.completed_at)
           ORDER BY date",
          @date_from,
        ])
      ).map { |r| { date: r["date"].to_s, count: r["count"].to_i } }

      # Merge by date
      merged = merge_time_series(
        { assets: assets_by_day, workflows: workflows_by_day },
        @date_from.to_date,
        @date_to.to_date
      )

      { combined: merged, assets: assets_by_day, workflows: workflows_by_day }
    rescue => e
      Rails.logger.error("[AnalyticsService] time_series failed: #{e.message}")
      { combined: [], assets: [], workflows: [] }
    end

    # ─── Breakdowns ──────────────────────────────────────────────────────────

    def breakdowns
      # See `stats`'s note on the analogous dashboard bug: bucketing must
      # happen *after* fetching all raw content-type counts, otherwise
      # multiple raw mime types that simplify to the same friendly label
      # (e.g. .doc + .docx → "Word Document") show up as separate/duplicate
      # entries instead of being merged into one.
      raw_type_counts = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT properties->>'content_type' AS type, COUNT(*) AS count
           FROM assets WHERE deleted_at IS NULL AND properties->>'content_type' IS NOT NULL#{folder_sql_clause}
           GROUP BY type",
        ])
      )
      grouped = Hash.new(0)
      raw_type_counts.each { |r| grouped[simplify_mime(r["type"])] += r["count"].to_i }
      by_type = grouped.sort_by { |_type, count| -count }.first(8).map { |type, count| { type: type, count: count } }

      status_scope = @folder_ids.present? ? Asset.unscoped.where(deleted_at: nil, folder_id: @folder_ids) : Asset.unscoped.where(deleted_at: nil)
      by_status = status_scope.group(:status).count
                               .map { |s, c| { status: s.to_s.humanize, count: c } }

      # When a folder filter is active, only break down among the *selected*
      # folders (not the whole tree) — otherwise "top folders" would just
      # re-list the entire folder tree regardless of the filter.
      folder_scope = @folder_ids.present? ? Folder.where(id: @folder_ids) : Folder.active
      top_folders = folder_scope.left_joins(:assets)
                          .where(assets: { deleted_at: nil })
                          .group("folders.id", "folders.name")
                          .order("COUNT(assets.id) DESC")
                          .limit(8)
                          .pluck("folders.name", "COUNT(assets.id) AS cnt")
                          .map { |name, cnt| { name: name, count: cnt.to_i } }

      workflow_base = @folder_ids.present? ? WorkflowInstance.joins(:asset).where(assets: { folder_id: @folder_ids }) : WorkflowInstance

      workflow_funnel = [
        { stage: "Triggered",  count: workflow_base.count },
        { stage: "In Review",  count: workflow_base.where(status: [ "pending", "in_progress" ]).count },
        { stage: "Approved",   count: workflow_base.where(status: "approved").count },
        { stage: "Rejected",   count: workflow_base.where(status: "rejected").count },
      ]

      by_user = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT u.email, COUNT(a.id) AS count
           FROM assets a JOIN users u ON a.user_id = u.id
           WHERE a.deleted_at IS NULL AND a.created_at >= ?#{folder_sql_clause("a.folder_id")}
           GROUP BY u.email ORDER BY count DESC LIMIT 10",
          @date_from,
        ])
      ).map { |r| { user: r["email"]&.split("@")&.first, count: r["count"].to_i } }

      {
        by_content_type: by_type,
        by_status:       by_status,
        top_folders:     top_folders,
        workflow_funnel: workflow_funnel,
        by_user:         by_user,
      }
    rescue => e
      Rails.logger.error("[AnalyticsService] breakdowns failed: #{e.message}")
      {}
    end

    # ─── AI Insights (threshold-based anomaly detection) ─────────────────────

    def ai_insights
      anomalies    = []
      suggestions  = []
      opportunities = []

      # 1. Upload spike detection
      daily_counts = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT DATE(created_at) AS date, COUNT(*) AS cnt
           FROM assets WHERE created_at >= ? AND deleted_at IS NULL#{folder_sql_clause}
           GROUP BY DATE(created_at) ORDER BY date",
          30.days.ago,
        ])
      ).map { |r| r["cnt"].to_i }

      if daily_counts.size >= 7
        avg   = daily_counts.sum.to_f / daily_counts.size
        max_c = daily_counts.max.to_i
        if avg > 0 && max_c > avg * 2.5
          anomalies << "📈 Upload spike detected: #{max_c} assets on peak day (#{(max_c / avg * 100 - 100).round}% above average)."
        end
      end

      active_scope = @folder_ids.present? ? Asset.active.where(folder_id: @folder_ids) : Asset.active

      # 2. Missing metadata alerts
      missing_alt = active_scope.where("properties->>'alt_text' IS NULL OR properties->>'alt_text' = ''").count
      total_active = active_scope.count
      if total_active > 0 && missing_alt.to_f / total_active > 0.2
        suggestions << "🏷️ #{missing_alt} assets (#{(missing_alt.to_f / total_active * 100).round}%) are missing alt_text. Run an AI enrichment batch to improve accessibility."
      end

      # 3. AI embedding gap
      embedding_scope = @folder_ids.present? ? AssetEmbedding.joins(:asset).where(assets: { folder_id: @folder_ids }) : AssetEmbedding
      covered = embedding_scope.count
      gap     = total_active - covered
      if gap > 50
        suggestions << "🤖 #{gap} assets lack vector embeddings. Trigger the AI Embedding job to unlock semantic search for these assets."
      end

      # 4. Trash accumulation
      trash_scope = @folder_ids.present? ? Asset.trashed.where(folder_id: @folder_ids) : Asset.trashed
      trash_count = trash_scope.count
      if trash_count > 100
        suggestions << "🗑️ #{trash_count} assets are in the bin. Consider running a permanent purge to reclaim storage."
      end

      # 5. License expiry forecast
      expiring_soon = active_scope.where(
        "(properties->>'license_expires_at')::timestamp < ?", 30.days.from_now
      ).count rescue 0
      if expiring_soon > 0
        anomalies << "⚠️ #{expiring_soon} assets have licenses expiring within 30 days. Review before campaign launch."
      end

      # 6. Workflow backlog
      overdue_scope = @folder_ids.present? ? WorkflowInstance.joins(:asset).where(assets: { folder_id: @folder_ids }) : WorkflowInstance
      overdue = overdue_scope.where(status: "pending")
                             .where("started_at < ?", 5.days.ago).count rescue 0
      if overdue > 0
        anomalies << "🚨 #{overdue} workflow reviews have been pending for over 5 days. Escalation may be needed."
      end

      # 7. Storage opportunity
      duplicate_scope = @folder_ids.present? ? IngestionBatch.where(destination_folder_id: @folder_ids) : IngestionBatch
      dup_gb = (duplicate_scope.sum(:duplicate_count).to_i * 5.0 / 1024).round(2)
      if dup_gb > 1
        opportunities << "💰 #{dup_gb} GB of duplicate storage has been blocked by the migration deduplication engine, saving approximately $#{(dup_gb * 0.023).round(2)}/month."
      end

      {
        anomalies:     anomalies,
        suggestions:   suggestions,
        opportunities: opportunities,
        generated_at:  Time.current,
      }
    rescue => e
      Rails.logger.error("[AnalyticsService] ai_insights failed: #{e.message}")
      { anomalies: [], suggestions: [], opportunities: [] }
    end

    # ─── Helpers ─────────────────────────────────────────────────────────────

    def compute_date_from(range_key)
      case range_key
      when "last_7_days"   then 7.days.ago.beginning_of_day
      when "last_30_days"  then 30.days.ago.beginning_of_day
      when "last_90_days"  then 90.days.ago.beginning_of_day
      when "this_year"     then Time.current.beginning_of_year
      when "this_quarter"  then Time.current.beginning_of_quarter
      else                      30.days.ago.beginning_of_day
      end
    end

    def range_label
      { "last_7_days" => "Last 7 Days", "last_30_days" => "Last 30 Days",
        "last_90_days" => "Last 90 Days", "this_year" => "Year to Date",
        "this_quarter" => "This Quarter" }[@range_key] || "Last 30 Days"
    end

    def simplify_mime(mime)
      return "Unknown" if mime.blank?
      case mime
      when /^image\//    then "Image (#{mime.split("/").last.upcase})"
      when /^video\//    then "Video (#{mime.split("/").last.upcase})"
      when /^application\/pdf/ then "PDF Document"
      when /^application\/(zip|x-zip)/ then "ZIP Archive"
      when /^application\/(vnd\.ms-excel|.*spreadsheet)/ then "Spreadsheet"
      when /^application\/(msword|.*wordprocessing)/ then "Word Document"
      when /^application\/(vnd\.ms-powerpoint|.*presentation)/ then "Presentation"
      else mime
      end
    end

    def merge_time_series(series_map, from_date, to_date)
      date_range = (from_date..to_date).to_a
      # Build a lookup hash for each series
      lookups = series_map.transform_values { |arr| arr.index_by { |r| r[:date] } }

      date_range.map do |date|
        row = { date: date.to_s }
        lookups.each { |key, lookup| row[key] = (lookup[date.to_s]&.dig(:count) || 0) }
        row
      end
    end

    # Builds a raw SQL " AND <column> IN (...)" fragment scoping a query to
    # the resolved folder filter, or "" when no filter is active. Ids are
    # individually quoted (not string-interpolated raw) to stay injection-safe.
    def folder_sql_clause(column = "folder_id")
      return "" if @folder_ids.blank?

      quoted = @folder_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(",")
      " AND #{column} IN (#{quoted})"
    end

    def folder_cache_key
      return "all" if @folder_ids.blank?

      Digest::MD5.hexdigest(@folder_ids.sort.join(","))
    end

    def folder_filter_summary
      { active: @folder_ids.present?, folder_ids: @folder_ids || [] }
    end
  end
end
