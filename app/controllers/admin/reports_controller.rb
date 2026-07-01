module Admin
  class ReportsController < Admin::BaseController
    before_action :set_report_definition, only: [ :show, :generate, :update, :destroy ]

    BUILT_IN_TYPES = %w[
      asset_library workflow_compliance storage_usage user_activity ai_coverage
      duplicates license_expiry collections audit_trail migration
    ].freeze

    # GET /admin/reports
    # Supports: ?active=true|false|all, ?q=search, ?page=, ?per_page=
    def index
      @active_view = "Reports"
      scope = ReportDefinition.order(:name)

      # filter by active status
      case params[:active]
      when "false"  then scope = scope.where(active: false)
      when "all"    then nil # no filter
      else               scope = scope.where(active: true)
      end

      # full-text search on name or report_type
      if (q = params[:q].presence)
        scope = scope.where("name ILIKE :q OR report_type ILIKE :q", q: "%#{q}%")
      end

      # category filter — supports built_in_only, custom_only, or exact report_type
      case params[:category].to_s
      when "built_in_only"
        scope = scope.where(report_type: BUILT_IN_TYPES)
      when "custom_only"
        scope = scope.where.not(report_type: BUILT_IN_TYPES)
      when ""
        nil # no filter
      else
        scope = scope.where(report_type: params[:category])
      end

      total = scope.count
      raw_per_page = params[:per_page].to_i
      per_page = raw_per_page.positive? ? [ raw_per_page, 100 ].min : 20
      page = [ params[:page].to_i, 1 ].max
      paginated = scope.offset((page - 1) * per_page).limit(per_page)

      respond_to do |format|
        format.html
        format.json do
          render json: {
            reports: paginated.map { |r| serialize_report(r) },
            meta: {
              total: total,
              page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil,
            },
            built_in_types: BUILT_IN_TYPES,
          }
        end
      end
    end

    # POST /admin/reports
    def create
      @report_definition = ReportDefinition.new(report_definition_params)
      if @report_definition.save
        render json: { report: serialize_report(@report_definition) }, status: :created
      else
        render json: { errors: @report_definition.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /admin/reports/:id
    def update
      if @report_definition.update(report_definition_params)
        render json: { report: serialize_report(@report_definition) }
      else
        render json: { errors: @report_definition.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /admin/reports/:id — soft-delete (deactivate)
    def destroy
      @report_definition.update!(active: false)
      render json: { message: "Report type deactivated." }
    end

    # GET /admin/reports/analytics?range=last_30_days
    # Lightweight aggregation endpoint for the live dashboard charts.
    # Uses Rails.cache (5 min TTL) to survive UI polling.
    def analytics
      range = params[:range].presence || "last_30_days"

      data = Reports::AnalyticsService.new(
        range,
        custom_from: parse_date(params[:from]),
        custom_to:   parse_date(params[:to])
      ).call

      render json: data
    rescue => e
      Rails.logger.error("[ReportsController#analytics] #{e.message}")
      render json: { error: "Analytics temporarily unavailable." }, status: :service_unavailable
    end

    # GET /admin/reports/:id
    def show
      snapshots = @report_definition.report_snapshots.order(created_at: :desc).limit(10)
      respond_to do |format|
        format.html
        format.json do
          render json: {
            report: @report_definition,
            recent_snapshots: format_snapshots(snapshots),
          }
        end
      end
    end

    # POST /admin/reports/:id/generate.json
    def generate
      # params[:format] is a Rails reserved word (set to "json" by the .json URL extension).
      # Read the export format from the raw request body params instead.
      fmt = request.request_parameters["format"].to_s.downcase
      unless %w[csv pdf xlsx].include?(fmt)
        return render json: { error: "Invalid format. Allowed: csv, pdf, xlsx" }, status: :unprocessable_entity
      end

      snapshot = @report_definition.report_snapshots.create!(
        format: fmt,
        parameters: permitted_params
      )

      Reports::GenerationJob.perform_later(snapshot.id)

      render json: { success: true, message: "Report queued.", snapshot_id: snapshot.id }, status: :accepted
    end

    # GET /admin/reports/asset_property_hints.json
    # Returns known property keys found in asset properties JSONB, plus
    # AI-analysis keys, for use in the dynamic query builder filter suggestions.
    def asset_property_hints
      # Extract top-level JSONB keys from recent assets (capped for performance)
      raw_keys = ActiveRecord::Base.connection.execute(
        "SELECT DISTINCT jsonb_object_keys(properties) AS key
         FROM (SELECT properties FROM assets WHERE properties != '{}' LIMIT 500) sub
         ORDER BY key"
      ).map { |r| r["key"] }

      # Categorise into known groups
      hints = {
        system: %w[content_type size file_size original_filename checksum_sha256 processed_at storage_path],
        image_analysis: %w[color_mode dominant_color orientation width height ai_tags ai_labels ai_description
                           image_analysis_status],
        editor: %w[editor_state],
        custom: (raw_keys - %w[content_type size file_size original_filename checksum_sha256
                               processed_at storage_path color_mode dominant_color orientation
                               width height ai_tags ai_labels ai_description image_analysis_status
                               editor_state]).first(50),
      }

      render json: { hints: hints }
    end

    private

    def set_report_definition
      @report_definition = ReportDefinition.find(params[:id])
    end

    def report_definition_params
      params.require(:report_definition).permit(
        :name, :report_type, :active,
        query_config: [
          :description, :content_type, :color_mode, :orientation,
          :status, :approved_status, :min_size_bytes, :max_size_bytes,
          :min_width, :max_width, :min_height, :max_height,
          :date_range, :from, :to, :include_archived,
          :dominant_color, :ai_label, :ai_tag,
          { folder_ids: [], custom_filters: {}, ai_tags: [], tags: [] }
        ]
      )
    end

    def permitted_params
      params.fetch(:parameters, {}).permit(
        :date_range, :from, :to, :folder_id, :user_id,
        :include_archived, :format, :grouping,
        :content_type_filter, :min_size_bytes, :max_size_bytes,
        :color_mode, :orientation, :status, :approved_status,
        :min_width, :max_width, :min_height, :max_height,
        folder_ids: []
      ).to_h
    end

    def parse_date(val)
      return nil if val.blank?
      Time.zone.parse(val)
    rescue ArgumentError
      nil
    end

    def serialize_report(r)
      {
        id:          r.id,
        name:        r.name,
        report_type: r.report_type,
        description: r.query_config&.dig("description"),
        active:      r.active,
        built_in:    BUILT_IN_TYPES.include?(r.report_type),
        created_at:  r.created_at&.iso8601,
        updated_at:  r.updated_at&.iso8601,
        query_config: r.query_config,
      }
    end

    def format_snapshots(snapshots)
      snapshots.map do |s|
        {
          id:           s.id,
          status:       s.status,
          format:       s.format,
          created_at:   s.created_at,
          download_url: s.completed? ? download_admin_report_snapshot_path(s) : nil,
          error_message: s.failed? ? s.error_message : nil,
        }
      end
    end
  end
end
