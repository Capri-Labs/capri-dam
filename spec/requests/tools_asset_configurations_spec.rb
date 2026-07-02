# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tools::AssetConfigurations coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  it "renders the asset configuration shell for admins" do
    sign_in admin

    get "/tools/asset_configurations"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-view="asset-configurations-screen"')
  end

  it "redirects non-admin users to the root path" do
    sign_in user

    get "/tools/asset_configurations"

    expect(response).to redirect_to(authenticated_root_path)
    expect(flash[:alert]).to include("Administrator privileges required")
  end

  it "returns 401 for JSON requests when unauthenticated" do
    get "/tools/asset_configurations", as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
