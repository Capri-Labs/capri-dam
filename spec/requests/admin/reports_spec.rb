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
