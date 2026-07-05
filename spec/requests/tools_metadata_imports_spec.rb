# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tools::MetadataImports coverage", type: :request do
  let(:user) { create(:user) }

  it "renders the metadata import shell for authenticated users and highlights the sidebar item" do
    sign_in user

    get "/tools/metadata_imports"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-view="metadata-imports-screen"')
    expect(assigns(:active_view)).to eq("MetadataImport")
    expect(response.body).to include('data-active-view="MetadataImport"')
  end

  it "returns 401 for unauthenticated HTML users" do
    get "/tools/metadata_imports"

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 for unauthenticated JSON requests" do
    get "/tools/metadata_imports", as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
