# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::Reports', type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:user)  { create(:user, admin: false) }

  let!(:built_in_report) do
    ReportDefinition.find_or_create_by!(report_type: 'asset_library') do |r|
      r.name = 'Asset Library Summary Test'
      r.active = true
      r.query_config = { 'description' => 'Test built-in report' }
    end
  end

  let!(:custom_report) do
    ReportDefinition.create!(
      name: "Custom Brand Report #{SecureRandom.hex(4)}",
      report_type: "brand_#{SecureRandom.hex(4)}",
      active: true,
      query_config: { 'description' => 'Custom report for brand assets' }
    )
  end

  describe 'GET /admin/reports.json' do
    context 'as admin' do
      before { sign_in admin }

      it 'returns paginated report definitions with meta' do
        get '/admin/reports.json', as: :json
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to include('reports', 'meta', 'built_in_types')
        expect(json['meta']).to include('total', 'page', 'per_page', 'total_pages')
      end

      it 'only returns active reports by default' do
        inactive = ReportDefinition.create!(name: 'Inactive', report_type: 'inactive_type', active: false)
        get '/admin/reports.json', as: :json
        ids = JSON.parse(response.body)['reports'].map { |r| r['id'] }
        expect(ids).not_to include(inactive.id)
        inactive.destroy
      end

      it 'returns all reports when active=all' do
        inactive = ReportDefinition.create!(name: 'Inactive2', report_type: 'inactive2', active: false)
        get '/admin/reports.json', params: { active: 'all' }, as: :json
        ids = JSON.parse(response.body)['reports'].map { |r| r['id'] }
        expect(ids).to include(inactive.id)
        inactive.destroy
      end

      it 'filters by search query' do
        get '/admin/reports.json', params: { q: custom_report.name.split(' ').last }, as: :json
        names = JSON.parse(response.body)['reports'].map { |r| r['name'] }
        expect(names).to include(custom_report.name)
      end

      it 'includes description from query_config' do
        get '/admin/reports.json', as: :json
        report = JSON.parse(response.body)['reports'].find { |r| r['id'] == built_in_report.id }
        expect(report['description']).to eq('Test built-in report')
      end

      it 'marks built-in types correctly' do
        get '/admin/reports.json', as: :json
        built_in = JSON.parse(response.body)['reports'].find { |r| r['id'] == built_in_report.id }
        custom   = JSON.parse(response.body)['reports'].find { |r| r['id'] == custom_report.id }
        expect(built_in['built_in']).to be true
        expect(custom['built_in']).to be false
      end

      it 'filters to built-in types only with category=built_in_only' do
        get '/admin/reports.json', params: { category: 'built_in_only', active: 'all' }, as: :json
        ids = JSON.parse(response.body)['reports'].map { |r| r['id'] }
        expect(ids).to include(built_in_report.id)
        expect(ids).not_to include(custom_report.id)
      end

      it 'filters to custom types only with category=custom_only' do
        get '/admin/reports.json', params: { category: 'custom_only', active: 'all' }, as: :json
        ids = JSON.parse(response.body)['reports'].map { |r| r['id'] }
        expect(ids).to include(custom_report.id)
        expect(ids).not_to include(built_in_report.id)
      end
    end

    it 'returns asset_property_hints' do
      sign_in admin
      get '/admin/reports/asset_property_hints.json', as: :json
      expect(response).to have_http_status(:ok)
      hints = JSON.parse(response.body)['hints']
      expect(hints).to have_key('system')
      expect(hints).to have_key('image_analysis')
      expect(hints).to have_key('custom')
    end

    it 'returns 401 for non-admin' do
      sign_in user
      get '/admin/reports.json', as: :json
      expect(response).to have_http_status(:redirect) # redirected to root
    end
  end

  describe 'POST /admin/reports.json' do
    before { sign_in admin }

    it 'creates a new report definition' do
      expect {
        post '/admin/reports.json',
          params: { report_definition: { name: 'My Custom Report', report_type: 'my_custom', active: true, query_config: { description: 'Test' } } },
          as: :json
      }.to change(ReportDefinition, :count).by(1)
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['report']['name']).to eq('My Custom Report')
      expect(json['report']['report_type']).to eq('my_custom')
    end

    it 'returns 422 with validation errors when name is blank' do
      post '/admin/reports.json',
        params: { report_definition: { name: '', report_type: 'test' } },
        as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to have_key('errors')
    end

    it 'returns 422 when report_type has invalid characters' do
      post '/admin/reports.json',
        params: { report_definition: { name: 'Test', report_type: 'invalid type!' } },
        as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 when name is duplicate' do
      post '/admin/reports.json',
        params: { report_definition: { name: custom_report.name, report_type: 'different_type' } },
        as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /admin/reports/:id.json' do
    before { sign_in admin }

    it 'updates the report definition name' do
      patch "/admin/reports/#{custom_report.id}.json",
        params: { report_definition: { name: 'Updated Brand Report' } },
        as: :json
      expect(response).to have_http_status(:ok)
      expect(custom_report.reload.name).to eq('Updated Brand Report')
    end

    it 'can activate an inactive report' do
      inactive = ReportDefinition.create!(name: 'Dormant', report_type: 'dormant', active: false)
      patch "/admin/reports/#{inactive.id}.json",
        params: { report_definition: { active: true } },
        as: :json
      expect(response).to have_http_status(:ok)
      expect(inactive.reload.active).to be true
      inactive.destroy
    end
  end

  describe 'DELETE /admin/reports/:id.json' do
    before { sign_in admin }

    it 'soft-deletes (deactivates) the report definition' do
      delete "/admin/reports/#{custom_report.id}.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(custom_report.reload.active).to be false
    end

    it 'returns a message' do
      delete "/admin/reports/#{custom_report.id}.json", as: :json
      expect(JSON.parse(response.body)['message']).to be_present
    end
  end

  describe 'POST /admin/reports/:id/generate.json' do
    before { sign_in admin }

    it 'queues a report snapshot with the correct export format' do
      # This test verifies the params[:format] Rails reserved-word bug is fixed.
      # params[:format] returns "json" (from URL extension), so we read from
      # request.request_parameters["format"] instead.
      allow(Reports::GenerationJob).to receive(:perform_later)

      post "/admin/reports/#{built_in_report.id}/generate.json",
        params: { format: 'pdf', parameters: { date_range: 'last_30_days' } },
        as: :json

      expect(response).to have_http_status(:accepted)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      snapshot = ReportSnapshot.last
      expect(snapshot.format).to eq('pdf')
    end

    it 'rejects an invalid export format' do
      post "/admin/reports/#{built_in_report.id}/generate.json",
        params: { format: 'docx', parameters: {} },
        as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to include('csv, pdf, xlsx')
    end
  end
end

# ---- merged from reports_coverage_spec.rb ----
RSpec.describe "Admin::Reports coverage additions", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let!(:active_report) { create(:report_definition, name: "Active Storage", report_type: "storage_usage", active: true, query_config: { "description" => "Storage" }) }
  let!(:inactive_report) { create(:report_definition, name: "Inactive Audit", report_type: "audit_trail", active: false) }
  let!(:custom_report) { create(:report_definition, name: "Brand Report", report_type: "brand_custom", active: true) }

  describe "GET /admin/reports.json" do
    before { sign_in admin }

    it "filters inactive, exact category, and caps pagination" do
      get "/admin/reports.json", params: { active: "false", category: "audit_trail", per_page: 500, page: -3 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["reports"].map { |row| row["id"] }).to eq([ inactive_report.id ])
      expect(response.parsed_body["meta"]).to include("page" => 1, "per_page" => 100)
    end

    it "renders the HTML shell for admins and redirects non-admins" do
      get "/admin/reports"
      expect(response).to have_http_status(:ok)

      sign_out admin
      sign_in user
      get "/admin/reports"
      expect(response).to redirect_to(authenticated_root_path)
    end
  end

  describe "show" do
    before { sign_in admin }

    it "returns report details with formatted recent snapshots" do
      completed = create(:report_snapshot, report_definition: active_report, status: :completed, format: "csv")
      completed.generated_file.attach(io: StringIO.new("csv"), filename: "report.csv", content_type: "text/csv")
      failed = create(:report_snapshot, report_definition: active_report, status: :failed, format: "pdf", error_message: "failed")

      get "/admin/reports/#{active_report.id}.json", as: :json

      expect(response).to have_http_status(:ok)
      snapshots = response.parsed_body["recent_snapshots"].index_by { |row| row["id"] }
      expect(snapshots[completed.id]["download_url"]).to include("/download")
      expect(snapshots[failed.id]["error_message"]).to eq("failed")
    end
  end

  describe "mutations" do
    before { sign_in admin }

    it "returns validation errors on update" do
      patch "/admin/reports/#{custom_report.id}.json", params: { report_definition: { name: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end

    it "queues xlsx generation and persists permitted parameters" do
      allow(Reports::GenerationJob).to receive(:perform_later)

      post "/admin/reports/#{active_report.id}/generate.json", params: {
        format: "xlsx",
        parameters: { date_range: "custom", from: "2026-01-01", to: "2026-01-31", folder_ids: %w[1 2], ignored: "no" },
      }, as: :json

      expect(response).to have_http_status(:accepted)
      snapshot = ReportSnapshot.last
      expect(snapshot.format).to eq("xlsx")
      expect(snapshot.parameters).to include("date_range" => "custom", "folder_ids" => %w[1 2])
      expect(snapshot.parameters).not_to have_key("ignored")
      expect(Reports::GenerationJob).to have_received(:perform_later).with(snapshot.id)
    end
  end

  describe "GET /admin/reports/analytics" do
    before { sign_in admin }

    it "returns analytics service data with parsed dates" do
      service = instance_double(Reports::AnalyticsService, call: { "totals" => { "reports" => 3 } })
      expect(Reports::AnalyticsService).to receive(:new).with("custom", custom_from: be_present, custom_to: be_nil).and_return(service)

      get "/admin/reports/analytics.json", params: { range: "custom", from: "2026-01-01", to: "not-a-date" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("totals" => { "reports" => 3 })
    end

    it "returns service unavailable when analytics raises" do
      allow(Reports::AnalyticsService).to receive(:new).and_raise(StandardError, "down")
      allow(Rails.logger).to receive(:error)

      get "/admin/reports/analytics.json", as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to include("temporarily unavailable")
    end
  end
end
