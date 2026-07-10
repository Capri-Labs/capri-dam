module Reports
  # AnalyticsService — powers the live dashboard charts.
  #
  # Design principles:
  # - Every query uses SQL aggregates (COUNT, SUM, GROUP BY) — never full scans
  # - Result sets are capped (LIMIT) to protect the query planner
  # - AI insights are threshold-based anomaly detection — no LLM call required
  # - Cached per date_from key for 5 minutes to survive polling spikes
  class AnalyticsService
    CACHE_TTL = 5.minutes

    def initialize(range_key = "last_30_days", custom_from: nil, custom_to: nil)
      @range_key  = range_key
      @date_from  = custom_from || compute_date_from(range_key)
      @date_to    = custom_to   || Time.current
    end

    def call
      cache_key = "reports_analytics:#{@range_key}:#{@date_from.to_date}"

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        {
          stats:       stats,
          time_series: time_series,
          breakdowns:  breakdowns,
          ai_insights: ai_insights,
        }
      end
    end

    private

    # ─── Stats (single aggregate query each) ─────────────────────────────────

    def stats
      asset_counts  = Asset.unscoped.select(
        "COUNT(*) FILTER (WHERE deleted_at IS NULL)                              AS total_assets",
        "COUNT(*) FILTER (WHERE status = 'ready'   AND deleted_at IS NULL)       AS active_assets",
        "COUNT(*) FILTER (WHERE status = 'pending' AND deleted_at IS NULL)       AS pending_assets",
        "COUNT(*) FILTER (WHERE created_at >= :from AND deleted_at IS NULL)      AS new_in_range",
        "COUNT(*) FILTER (WHERE deleted_at IS NOT NULL)                          AS in_trash"
      ).where("1=1").limit(1).to_a.first
                            .attributes.transform_values(&:to_i)

      workflow_counts = WorkflowInstance.select(
        "COUNT(*) FILTER (WHERE status IN ('pending','in_progress'))             AS active_workflows",
        "COUNT(*) FILTER (WHERE status = 'pending')                              AS pending_approvals",
        "COUNT(*) FILTER (WHERE status = 'approved' AND updated_at >= :from)     AS approved_in_range",
        "COUNT(*) FILTER (WHERE status = 'rejected' AND updated_at >= :from)     AS rejected_in_range",
        "ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - started_at))/3600)::numeric, 1) AS avg_approval_hours"
      ).where("1=1").limit(1).to_a.first&.attributes&.except("id") || {}

      embedding_counts = AssetEmbedding.select(
        "COUNT(*) AS with_embedding"
      ).limit(1).to_a.first&.attributes || {}

      duplicate_count = IngestionBatch.sum(:duplicate_count).to_i

      storage_gb = ActiveRecord::Base.connection.select_value(
        "SELECT ROUND(COALESCE(SUM((properties->>'size')::bigint),0)::numeric / 1073741824, 2) FROM assets WHERE deleted_at IS NULL AND properties->>'size' IS NOT NULL"
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
           WHERE created_at >= ? AND deleted_at IS NULL
           GROUP BY DATE(created_at)
           ORDER BY date",
          @date_from,
        ])
      ).map { |r| { date: r["date"].to_s, count: r["count"].to_i } }

      # Workflows completed per day
      workflows_by_day = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT DATE(completed_at) AS date, COUNT(*) AS count
           FROM workflow_instances
           WHERE completed_at >= ? AND status = 'approved'
           GROUP BY DATE(completed_at)
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
      by_type = ActiveRecord::Base.connection.select_all(
        "SELECT properties->>'content_type' AS type, COUNT(*) AS count
         FROM assets WHERE deleted_at IS NULL AND properties->>'content_type' IS NOT NULL
         GROUP BY type ORDER BY count DESC LIMIT 8"
      ).map { |r| { type: simplify_mime(r["type"]), count: r["count"].to_i } }

      by_status = Asset.unscoped.where(deleted_at: nil)
                       .group(:status).count
                       .map { |s, c| { status: s.to_s.humanize, count: c } }

      top_folders = Folder.active.left_joins(:assets)
                          .where(assets: { deleted_at: nil })
                          .group("folders.id", "folders.name")
                          .order("COUNT(assets.id) DESC")
                          .limit(8)
                          .pluck("folders.name", "COUNT(assets.id) AS cnt")
                          .map { |name, cnt| { name: name, count: cnt.to_i } }

      workflow_funnel = [
        { stage: "Triggered",  count: WorkflowInstance.count },
        { stage: "In Review",  count: WorkflowInstance.where(status: [ "pending", "in_progress" ]).count },
        { stage: "Approved",   count: WorkflowInstance.where(status: "approved").count },
        { stage: "Rejected",   count: WorkflowInstance.where(status: "rejected").count },
      ]

      by_user = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT u.email, COUNT(a.id) AS count
           FROM assets a JOIN users u ON a.user_id = u.id
           WHERE a.deleted_at IS NULL AND a.created_at >= ?
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
           FROM assets WHERE created_at >= ? AND deleted_at IS NULL
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

      # 2. Missing metadata alerts
      missing_alt = Asset.active.where("properties->>'alt_text' IS NULL OR properties->>'alt_text' = ''").count
      total_active = Asset.active.count
      if total_active > 0 && missing_alt.to_f / total_active > 0.2
        suggestions << "🏷️ #{missing_alt} assets (#{(missing_alt.to_f / total_active * 100).round}%) are missing alt_text. Run an AI enrichment batch to improve accessibility."
      end

      # 3. AI embedding gap
      covered = AssetEmbedding.count
      gap     = total_active - covered
      if gap > 50
        suggestions << "🤖 #{gap} assets lack vector embeddings. Trigger the AI Embedding job to unlock semantic search for these assets."
      end

      # 4. Trash accumulation
      trash_count = Asset.trashed.count
      if trash_count > 100
        suggestions << "🗑️ #{trash_count} assets are in the bin. Consider running a permanent purge to reclaim storage."
      end

      # 5. License expiry forecast
      expiring_soon = Asset.active.where(
        "(properties->>'license_expires_at')::timestamp < ?", 30.days.from_now
      ).count rescue 0
      if expiring_soon > 0
        anomalies << "⚠️ #{expiring_soon} assets have licenses expiring within 30 days. Review before campaign launch."
      end

      # 6. Workflow backlog
      overdue = WorkflowInstance.where(status: "pending")
                                .where("started_at < ?", 5.days.ago).count rescue 0
      if overdue > 0
        anomalies << "🚨 #{overdue} workflow reviews have been pending for over 5 days. Escalation may be needed."
      end

      # 7. Storage opportunity
      dup_gb = (IngestionBatch.sum(:duplicate_count).to_i * 5.0 / 1024).round(2)
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
  end
end
