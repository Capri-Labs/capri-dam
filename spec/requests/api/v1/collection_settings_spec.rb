require "rails_helper"

RSpec.describe "Api::V1::CollectionSettings", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "GET /api/v1/collection_settings" do
    it "requires authentication" do
      get api_v1_collection_settings_path, as: :json

      expect(response.status).to be_in([ 401, 302 ])
    end

    it "returns defaults merged with persisted settings" do
      sign_in user
      Setting.set("collection_settings", { "default_visibility" => "private", "max_assets_per_collection" => 25 })

      get api_v1_collection_settings_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "default_visibility" => "private",
        "max_assets_per_collection" => 25,
        "smart_rule_schedule" => "daily",
      )
    end
  end

  describe "PATCH /api/v1/collection_settings" do
    it "rejects non-admin users" do
      sign_in user

      patch api_v1_collection_settings_path,
            params: { settings: { default_visibility: "private" } },
            as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "updates settings for admins" do
      sign_in admin

      patch api_v1_collection_settings_path,
            params: {
              settings: {
                default_visibility: "private",
                max_assets_per_collection: 50,
                auto_cdn_purge: false,
              },
            },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to eq("Collection settings saved successfully.")
      expect(Setting.get("collection_settings")).to include(
        "default_visibility" => "private",
        "max_assets_per_collection" => 50,
        "auto_cdn_purge" => false,
      )
    end

    it "returns unprocessable entity when persistence fails" do
      sign_in admin
      allow(Setting).to receive(:set).and_raise(StandardError, "save failed")

      patch api_v1_collection_settings_path,
            params: { settings: { default_visibility: "private" } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "save failed")
    end
  end
end
