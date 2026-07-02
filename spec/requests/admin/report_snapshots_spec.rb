require "rails_helper"

RSpec.describe "Admin::ReportSnapshots coverage", type: :request do
  let(:definition) { create(:report_definition, name: "Asset Audit", report_type: "asset_audit") }

  describe "GET /admin/report_snapshots.json" do
    it "returns recent snapshots with download urls and failed errors" do
      completed = create(:report_snapshot, report_definition: definition, status: :completed, format: "csv")
      completed.generated_file.attach(io: StringIO.new("id,name\n1,A"), filename: "report.csv", content_type: "text/csv")
      failed = create(:report_snapshot, report_definition: definition, status: :failed, format: "pdf", error_message: "boom")
      pending = create(:report_snapshot, report_definition: definition, status: :pending, format: "xlsx")

      get "/admin/report_snapshots.json", as: :json

      expect(response).to have_http_status(:ok)
      by_id = response.parsed_body["snapshots"].index_by { |row| row["id"] }
      expect(by_id[completed.id]).to include("report_name" => "Asset Audit", "format" => "CSV", "status" => "completed")
      expect(by_id[completed.id]["download_url"]).to include("/admin/report_snapshots/#{completed.id}/download")
      expect(by_id[failed.id]["error_message"]).to eq("boom")
      expect(by_id[pending.id]["download_url"]).to be_nil
    end

    it "returns an empty list when no snapshots exist" do
      get "/admin/report_snapshots.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["snapshots"]).to eq([])
    end
  end

  describe "GET /admin/report_snapshots/:id/download" do
    it "redirects completed snapshots with attached files to the blob" do
      snapshot = create(:report_snapshot, report_definition: definition, status: :completed, format: "csv")
      snapshot.generated_file.attach(io: StringIO.new("hello"), filename: "hello.csv", content_type: "text/csv")

      get "/admin/report_snapshots/#{snapshot.id}/download"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/rails/active_storage/blobs/redirect")
    end

    it "returns not found when the file is missing or not completed" do
      snapshot = create(:report_snapshot, report_definition: definition, status: :processing, format: "csv")

      get "/admin/report_snapshots/#{snapshot.id}/download", as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("File not ready")
    end
  end
end
