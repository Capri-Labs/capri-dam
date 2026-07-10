require "rails_helper"

RSpec.describe "Api::V1::UploadLimitsController", type: :request do
  let(:admin_user) { FactoryBot.create(:user, admin: true) }

  describe "GET /api/v1/upload_limits" do
    it "returns the default 2GB limit when no override is configured" do
      sign_in admin_user
      get "/api/v1/upload_limits"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["max_upload_size_bytes"]).to eq(2.gigabytes)
    end

    it "returns the configured override when a Setting exists" do
      Setting.set("max_upload_size_bytes", 5.gigabytes)
      sign_in admin_user
      get "/api/v1/upload_limits"

      expect(JSON.parse(response.body)["max_upload_size_bytes"]).to eq(5.gigabytes)
    end
  end

  describe "PUT /api/v1/upload_limits" do
    it "persists a new limit and returns a success message" do
      sign_in admin_user
      put "/api/v1/upload_limits", params: { max_upload_size_bytes: 3.gigabytes }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["max_upload_size_bytes"]).to eq(3.gigabytes)
      expect(body["message"]).to eq("Upload size limit saved successfully.")
      expect(Setting.get("max_upload_size_bytes")).to eq(3.gigabytes)
    end

    it "rejects a zero or negative value with 422" do
      sign_in admin_user
      put "/api/v1/upload_limits", params: { max_upload_size_bytes: 0 }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("positive number")
    end
  end
end
