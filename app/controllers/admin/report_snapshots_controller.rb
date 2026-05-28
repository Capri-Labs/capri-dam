module Admin
  class ReportSnapshotsController < ApplicationController

    # GET /admin/report_snapshots.json
    def index
      # Fetch the 50 most recent snapshots and avoid N+1 queries
      snapshots = ReportSnapshot.includes(:report_definition).order(created_at: :desc).limit(50)

      render json: {
        snapshots: snapshots.map do |snapshot|
          {
            id: snapshot.id,
            report_name: snapshot.report_definition.name,
            format: snapshot.format.upcase,
            status: snapshot.status,
            created_at: snapshot.created_at.strftime("%b %d, %Y at %H:%M"),
            download_url: snapshot.completed? ? download_admin_report_snapshot_path(snapshot) : nil,
            error_message: snapshot.failed? ? snapshot.error_message : nil
          }
        end
      }
    end

    # GET /admin/report_snapshots/:id/download
    def download
      snapshot = ReportSnapshot.find(params[:id])

      unless snapshot.completed? && snapshot.generated_file.attached?
        return render json: { error: "File not ready or missing." }, status: :not_found
      end

      redirect_to rails_blob_path(snapshot.generated_file, disposition: "attachment")
    end
  end
end