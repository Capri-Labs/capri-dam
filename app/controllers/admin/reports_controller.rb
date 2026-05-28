module Admin
  class ReportsController < ApplicationController
    before_action :set_report_definition, only: [:show, :generate]

    # GET /admin/reports
    # GET /admin/reports.json
    def index
      @reports = ReportDefinition.where(active: true).order(:name)

      respond_to do |format|
        # HTML: Renders app/views/admin/reports/index.html.erb
        # (Where your <div data-view="reports"> lives)
        format.html

        # JSON: Used by your React useEffect fetch calls
        format.json { render json: { reports: @reports } }
      end
    end

    # GET /admin/reports/:id
    # GET /admin/reports/:id.json
    def show
      snapshots = @report_definition.report_snapshots.order(created_at: :desc).limit(10)

      respond_to do |format|
        format.html # Renders app/views/admin/reports/show.html.erb (if you build a dedicated view later)

        format.json do
          snapshots_json = snapshots.map do |snapshot|
            {
              id: snapshot.id,
              status: snapshot.status,
              format: snapshot.format,
              created_at: snapshot.created_at,
              # Only provide a download URL if the background job finished successfully
              download_url: snapshot.completed? ? download_admin_report_snapshot_path(snapshot) : nil,
              error_message: snapshot.failed? ? snapshot.error_message : nil
            }
          end

          render json: {
            report: @report_definition,
            recent_snapshots: snapshots_json
          }
        end
      end
    end

    # POST /admin/reports/:id/generate.json
    def generate
      format = params[:format].to_s.downcase

      unless %w[csv pdf xlsx].include?(format)
        return render json: { error: "Invalid format. Allowed: csv, pdf, xlsx" }, status: :unprocessable_entity
      end

      # 1. Create the Pending Snapshot
      snapshot = @report_definition.report_snapshots.create!(
        format: format,
        parameters: params.fetch(:parameters, {}).permit!
      )

      # 2. Queue the Sidekiq Worker
      Reports::GenerationJob.perform_later(snapshot.id)

      # 3. Immediately return the ID so the UI can start polling for completion
      # (This remains JSON-only since it's an API trigger from React)
      render json: {
        success: true,
        message: "Report generation started.",
        snapshot_id: snapshot.id
      }, status: :accepted
    end

    private

    def set_report_definition
      @report_definition = ReportDefinition.find(params[:id])
    end
  end
end