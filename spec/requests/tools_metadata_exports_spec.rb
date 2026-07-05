# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tools::MetadataExports coverage", type: :request do
  let(:user) { create(:user) }

  it "renders the metadata export shell for authenticated users and highlights the sidebar item" do
    sign_in user

    get "/tools/metadata_exports"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-view="metadata-exports-screen"')
    expect(assigns(:active_view)).to eq("MetadataExport")
    expect(response.body).to include('data-active-view="MetadataExport"')
  end

  it "returns 401 for unauthenticated HTML users" do
    get "/tools/metadata_exports"

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 for unauthenticated JSON requests" do
    get "/tools/metadata_exports", as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
