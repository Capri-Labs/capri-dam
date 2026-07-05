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

  it "renders all migration shells for admins and highlights the matching sidebar item" do
    sign_in admin

    {
      "/admin/migrations/ingestion"  => "Ingestion Engine",
      "/admin/migrations/connectors" => "Legacy Connectors",
      "/admin/migrations/health"     => "Data Health",
    }.each do |path, active_view|
      get path
      expect(response).to have_http_status(:ok)
      expect(assigns(:active_view)).to eq(active_view)
      expect(response.body).to include(%(data-active-view="#{active_view}"))
    end
  end
end
