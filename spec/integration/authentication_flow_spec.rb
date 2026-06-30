# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication flow", type: :integration, aggregate_failures: true do
  let(:admin_user) { create(:user, :admin, password: "password123", password_confirmation: "password123") }
  let(:session_headers) { { "ACCEPT" => "application/json" } }
  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
    }
  end

  before do
    create(:asset, user: admin_user, status: :ready, title: "Auth Asset")
  end

  it "covers session login, PATs, OAuth client credentials, and logout" do
    post "/users/sign_in",
         params: { user: { email: admin_user.email, password: "password123" } }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:ok)
    expect(response.headers["Set-Cookie"]).to be_present

    post "/users/sign_in",
         params: { user: { email: admin_user.email, password: "wrong-password" } }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:unauthorized).or have_http_status(:found)

    post "/profile/personal_access_tokens",
         params: {
           token: {
             name: "Integration PAT",
             scopes: "write",
             expires_at: 1.day.from_now.iso8601,
           },
         }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:created)
    pat_response = json_body.fetch("token")
    raw_token = pat_response.fetch("raw_token")

    get "/api/v1/assets", headers: { "Authorization" => "Bearer #{raw_token}" }
    expect(response).to have_http_status(:ok)
    expect(json_body).to be_an(Array)

    delete "/profile/personal_access_tokens/#{pat_response.fetch("id")}", headers: session_headers
    expect(response).to have_http_status(:ok)

    delete "/users/sign_out", headers: session_headers

    get "/api/v1/assets", headers: { "Authorization" => "Bearer #{raw_token}" }
    expect(response).to have_http_status(:unauthorized)

    oauth_app = Doorkeeper::Application.create!(
      name: "Integration OAuth Client",
      redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
      scopes: "read write"
    )

    post "/oauth/token",
         params: {
           grant_type: "client_credentials",
           client_id: oauth_app.uid,
           client_secret: oauth_app.secret,
           scope: "read",
         }
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("access_token")).to be_present

    delete "/users/sign_out", headers: session_headers
    expect(response).to have_http_status(:found).or have_http_status(:see_other).or have_http_status(:no_content)

    get "/api/v1/assets"
    expect(response).to have_http_status(:unauthorized).or have_http_status(:found).or have_http_status(:see_other)
  end
end
