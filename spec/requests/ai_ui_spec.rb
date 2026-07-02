# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ai::Ui coverage", type: :request do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }

  it "renders the copilot shell for any authenticated user" do
    sign_in user

    get "/ai/copilot"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-view="semantic-copilot-screen"')
  end

  it "renders each admin AI shell for admins" do
    sign_in admin

    {
      "/ai/agents" => "ai-automations-screen",
      "/ai/tasks" => "ai-batch-processing-screen",
      "/ai/lab/playground" => "ai-lab-playground-screen",
      "/ai/governance/provenance" => "ai-provenance-c2pa-screen",
      "/ai/models/hub" => "ai-style-model-hub-screen",
    }.each do |path, view|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(view)
    end
  end

  it "redirects unauthenticated users to sign in" do
    get "/ai/copilot"

    expect(response).to redirect_to(new_user_session_path)
  end

  it "forbids non-admin users from admin AI shells" do
    sign_in user

    get "/ai/agents"

    expect(response).to have_http_status(:forbidden)
  end
end
