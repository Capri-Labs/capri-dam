# frozen_string_literal: true

module Api
  module V1
    class DashboardController < ApplicationController
      before_action :authenticate_hybrid!

      # @swagger
      # get:
      #   tags: [Dashboard]
      #   summary: Get dashboard overview statistics
      #   security:
      #     - Bearer: []
      #   responses:
      #     '200':
      #       description: Dashboard statistics
      #     '401':
      #       description: Unauthorized
      def overview
        render json: {
          kpis: build_kpis,
          asset_growth: build_asset_growth,
          assets_by_type: build_assets_by_type,
          storage: build_storage,
          recent_assets: build_recent_assets,
          workflow_summary: build_workflow_summary,
          ai_insights: build_ai_insights,
        }
      end

      private

      def build_kpis
        scope = Asset.active
        {
          total_assets: scope.count,
          total_folders: Folder.count,
          total_users: User.count,
          assets_added_7d: scope.where("created_at >= ?", 7.days.ago).count,
          published_assets: scope.where(status: "published").count,
          draft_assets: scope.where(status: "draft").count,
          workflow_tasks_approved: WorkflowTask.where(status: "approved").count,
          metadata_schemas: MetadataSchema.count,
        }
      end

      def build_asset_growth
        months = (0..5).map { |n| n.months.ago.beginning_of_month }.reverse
        months.map do |month|
          count = Asset.active
                       .where(created_at: month..(month + 1.month))
                       .count
          { month: month.strftime("%b %Y"), count: count }
        end
      end

      def build_assets_by_type
        rows = ActiveRecord::Base.connection.execute(
          Arel.sql(
            "SELECT COALESCE(properties->>'content_type', 'unknown') as ctype, COUNT(*) as cnt\n" \
            "FROM assets WHERE deleted_at IS NULL\n" \
            "GROUP BY ctype ORDER BY cnt DESC LIMIT 10"
          )
        )
        rows.map { |row| { type: simplify_mime(row["ctype"]), count: row["cnt"].to_i } }
      end

      def simplify_mime(mime)
        return "Unknown" if mime.blank? || mime == "unknown"

        case mime
        when /image/ then "Images"
        when /video/ then "Videos"
        when /audio/ then "Audio"
        when /pdf/ then "PDF"
        when /document|word|excel|spreadsheet|presentation/ then "Documents"
        else "Other"
        end
      end

      def build_storage
        result = ActiveRecord::Base.connection.execute(
          Arel.sql(
            "SELECT SUM((properties->>'file_size')::bigint) as total FROM assets " \
            "WHERE deleted_at IS NULL AND properties->>'file_size' IS NOT NULL"
          )
        )
        total_bytes = result.first&.dig("total").to_i
        { total_bytes: total_bytes, total_human: format_bytes(total_bytes) }
      end

      def format_bytes(bytes)
        return "0 B" if bytes.zero?

        units = %w[B KB MB GB TB]
        exp = (Math.log(bytes) / Math.log(1024)).floor
        exp = [ exp, units.length - 1 ].min
        "#{(bytes.to_f / (1024**exp)).round(1)} #{units[exp]}"
      end

      def build_recent_assets
        Asset.active.order(created_at: :desc).limit(20).map do |asset|
          {
            id: asset.id,
            uuid: asset.uuid,
            title: asset.title || asset.properties&.dig("original_filename") || "Untitled",
            content_type: asset.properties&.dig("content_type") || "unknown",
            file_size: asset.properties&.dig("file_size").to_i,
            created_at: asset.created_at.iso8601,
            status: asset.status || "draft",
          }
        end
      end

      def build_workflow_summary
        counts = WorkflowTask.group(:status).count
        {
          total: WorkflowTask.count,
          by_status: counts,
          approved: counts.fetch("approved", 0),
          rejected: counts.fetch("rejected", 0),
          canceled: counts.fetch("canceled", 0),
        }
      end

      def build_ai_insights
        insights = []
        failed_analysis = Asset.active
                               .where("properties->>'image_analysis_status' = 'failed'")
                               .count
        insights << { type: "warning", key: "failed_analysis", count: failed_analysis } if failed_analysis > 0

        no_schema = Asset.active
                         .where("properties->>'applied_schema_name' IS NULL")
                         .count
        insights << { type: "info", key: "no_schema", count: no_schema } if no_schema > 0

        recent_24h = Asset.active.where("created_at >= ?", 24.hours.ago).count
        insights << { type: "success", key: "recent_24h", count: recent_24h } if recent_24h > 0

        insights
      end
    end
  end
end
