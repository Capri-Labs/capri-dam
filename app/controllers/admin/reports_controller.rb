module Admin
  class ReportsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :set_report_definition, only: [ :show, :generate ]

    # GET /admin/reports
    def index
      @active_view = "Reports"
      @reports = ReportDefinition.where(active: true).order(:name)
      respond_to do |format|
        format.html
        format.json { render json: { reports: @reports } }
      end
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
      fmt = params[:format].to_s.downcase
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

    private

    def set_report_definition
      @report_definition = ReportDefinition.find(params[:id])
    end

    def require_admin!
      redirect_to root_path, alert: "Access denied." unless current_user&.admin?
    end

    def permitted_params
      params.fetch(:parameters, {}).permit(
        :date_range, :from, :to, :folder_id, :user_id,
        :include_archived, :format, :grouping
      ).to_h
    end

    def parse_date(val)
      return nil if val.blank?
      Time.zone.parse(val)
    rescue ArgumentError
      nil
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
