require 'rails_helper'

# Coverage for the custom "funny 404" screen (ApplicationController#render_not_found)
# and its two triggers:
#
#   1. ActiveRecord::RecordNotFound raised inside a matched controller action
#      (e.g. Api::V1::AssetDownloadsController#set_download looking up a
#      download that belongs to someone else / no longer exists — the bug
#      report this feature was built for).
#   2. A route that matches nothing at all (config/routes.rb catch-all →
#      ErrorsController#not_found).
#
# Both must respond appropriately per format: JSON clients get a small
# structured body (so the SPA's existing fetch error handling is unaffected),
# HTML/browser navigation gets the illustrated 404 page instead of a raw
# framework stack trace.
RSpec.describe 'Custom 404 handling', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'ActiveRecord::RecordNotFound inside a controller action' do
    it 'renders JSON 404 for API/fetch requests (Accept: application/json)' do
      get '/api/v1/asset_downloads/999999', headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => I18n.t('errors.not_found.json_message'))
    end

    it 'renders the illustrated HTML 404 page for browser navigation (Accept: text/html)' do
      get '/api/v1/asset_downloads/999999', headers: { 'Accept' => 'text/html' }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(I18n.t('errors.not_found.heading'))
      expect(response.body).to include(CGI.escapeHTML(I18n.t('errors.not_found.message')))
    end

    it "still 404s (via the same handler) when the record belongs to another user" do
      other_download = create(:asset_download, user: create(:user))

      get "/api/v1/asset_downloads/#{other_download.id}", headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => I18n.t('errors.not_found.json_message'))
    end
  end

  describe 'Unmatched routes' do
    it 'renders the illustrated HTML 404 page for a completely unknown path' do
      get '/this/path/does/not/exist', headers: { 'Accept' => 'text/html' }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(I18n.t('errors.not_found.heading'))
    end

    it 'renders JSON 404 for an unknown API path' do
      get '/api/v1/this_endpoint_does_not_exist', headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => I18n.t('errors.not_found.json_message'))
    end
  end

  describe 'controllers with their own rescue_from ActiveRecord::RecordNotFound' do
    it "still use their own handler, not the shared one (e.g. WorkflowsController)" do
      get '/workflows/999999', headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:not_found)
      # WorkflowsController's own handler renders `{ error: e.message }`
      # (the raw ActiveRecord message), not the shared friendly copy —
      # confirms per-controller overrides still take precedence.
      expect(response.parsed_body['error']).to match(/Couldn't find Workflow/)
    end
  end
end
