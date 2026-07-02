# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::TemplateSuggestions coverage", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "returns the static template suggestions for authenticated users" do
    get "/api/v1/ai/template_suggestions", as: :json

    expect(response).to have_http_status(:ok)
    suggestions = JSON.parse(response.body)["suggestions"]
    expect(suggestions.size).to eq(2)
    expect(suggestions.map { |suggestion| suggestion["id"] }).to contain_exactly("subject-personalization", "cta-clarity")
  end

  it "returns 401 for unauthenticated users" do
    sign_out user

    get "/api/v1/ai/template_suggestions", as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
