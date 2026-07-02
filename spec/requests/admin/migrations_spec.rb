require "rails_helper"

RSpec.describe "Admin::Migrations coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  it "requires authentication" do
    get "/admin/migrations/ingestion"
    expect(response).to have_http_status(:unauthorized).or redirect_to(new_user_session_path)
  end

  it "forbids non-admin users" do
    sign_in user
    get "/admin/migrations/connectors"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders all migration shells for admins" do
    sign_in admin

    [ "/admin/migrations/ingestion", "/admin/migrations/connectors", "/admin/migrations/health" ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
    end
  end
end
