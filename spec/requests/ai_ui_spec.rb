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
    expect(assigns(:active_view)).to eq("Semantic Search")
    expect(response.body).to include('data-active-view="Semantic Search"')
  end

  it "renders each admin AI shell for admins and highlights the matching sidebar item" do
    sign_in admin

    {
      "/ai/agents"                => [ "ai-automations-screen",       "Agent Automations" ],
      "/ai/tasks"                 => [ "ai-batch-processing-screen",  "Metadata Extraction" ],
      "/ai/lab/playground"        => [ "ai-lab-playground-screen",    "Prompt Playground" ],
      "/ai/governance/provenance" => [ "ai-provenance-c2pa-screen",   "Content Authenticity" ],
      "/ai/models/hub"            => [ "ai-style-model-hub-screen",   "Brand Synthesis" ],
    }.each do |path, (view, active_view)|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(view)
      expect(assigns(:active_view)).to eq(active_view)
      expect(response.body).to include(%(data-active-view="#{active_view}"))
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
