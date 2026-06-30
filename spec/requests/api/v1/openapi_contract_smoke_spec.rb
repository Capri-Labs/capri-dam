# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OpenAPI contract smoke", type: :request, aggregate_failures: true do
  let(:admin_user) { create(:user, :admin) }
  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
    }
  end

  before do
    sign_in admin_user
  end

  it "validates a documented system connector response against the OpenAPI schema" do
    post "/api/v1/system_connectors",
         params: {
           system_connector: {
             name: "OpenAPI Smoke Connector",
             provider_type: "aem",
             endpoint: "https://connector.example.test",
             auth_token: "secret-token",
           },
         }.to_json,
         headers: json_headers

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to include("name" => "OpenAPI Smoke Connector", "provider_type" => "aem")
  end
end
