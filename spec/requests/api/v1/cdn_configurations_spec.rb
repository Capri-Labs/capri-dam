require "rails_helper"

RSpec.describe "Api::V1::CdnConfigurations", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "GET /api/v1/cdn_configurations" do
    it "requires authentication" do
      get api_v1_cdn_configurations_path, as: :json

      expect(response.status).to be_in([ 401, 302 ])
    end

    it "returns masked configurations for authenticated users" do
      sign_in user
      fastly = instance_double(CdnConfiguration, provider: "fastly", is_active: true, settings: { "api_key" => "abcdef1234" })
      allow(CdnConfiguration).to receive(:all).and_return([ fastly ])

      get api_v1_cdn_configurations_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("fastly", "settings", "api_key")).to eq("••••••••1234")
      expect(response.parsed_body["cloudflare"]).to eq("is_active" => false, "settings" => {})
    end

    it "renders blank settings without mask characters" do
      sign_in user
      fastly = instance_double(CdnConfiguration, provider: "fastly", is_active: true, settings: { "api_key" => "" })
      allow(CdnConfiguration).to receive(:all).and_return([ fastly ])

      get api_v1_cdn_configurations_path, as: :json

      expect(response.parsed_body.dig("fastly", "settings", "api_key")).to eq("")
    end

    it "passes image_optimizer_formats through unmasked (it is configuration, not a secret)" do
      sign_in user
      fastly = instance_double(
        CdnConfiguration,
        provider: "fastly",
        is_active: true,
        settings: { "api_key" => "abcdef1234", "image_optimizer_formats" => [ "webp", "avif" ] }
      )
      allow(CdnConfiguration).to receive(:all).and_return([ fastly ])

      get api_v1_cdn_configurations_path, as: :json

      expect(response.parsed_body.dig("fastly", "settings", "image_optimizer_formats")).to eq([ "webp", "avif" ])
      expect(response.parsed_body.dig("fastly", "settings", "api_key")).to eq("••••••••1234")
    end
  end

  describe "PUT /api/v1/cdn_configurations" do
    it "rejects non-admin updates" do
      sign_in user

      put api_v1_cdn_configurations_path,
          params: { provider: "fastly", is_active: true, settings: { api_key: "new-key" } },
          as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "updates a provider configuration for admins" do
      sign_in admin
      config = instance_double(CdnConfiguration, settings: { "api_key" => "old-key" }, errors: instance_double(ActiveModel::Errors, full_messages: []))
      allow(config).to receive(:is_active=)
      allow(config).to receive(:settings=)
      allow(config).to receive(:save).and_return(true)
      allow(CdnConfiguration).to receive(:find_or_initialize_by).with(provider: "fastly").and_return(config)

      put api_v1_cdn_configurations_path,
          params: { provider: "fastly", is_active: true, settings: { api_key: "••••masked", service_id: "svc_1" } },
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(config).to have_received(:is_active=).with(true)
      expect(config).to have_received(:settings=).with("api_key" => "old-key", "service_id" => "svc_1")
    end

    it "returns validation errors" do
      sign_in admin
      errors = instance_double(ActiveModel::Errors, full_messages: [ "Provider can't be blank" ])
      config = instance_double(CdnConfiguration, settings: {}, errors: errors)
      allow(config).to receive(:is_active=)
      allow(config).to receive(:settings=)
      allow(config).to receive(:save).and_return(false)
      allow(CdnConfiguration).to receive(:find_or_initialize_by).with(provider: "").and_return(config)

      put api_v1_cdn_configurations_path,
          params: { provider: "", is_active: true, settings: {} },
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to eq([ "Provider can't be blank" ])
    end

    it "keeps existing settings when the request omits nested settings params" do
      sign_in admin
      config = instance_double(CdnConfiguration, settings: { "api_key" => "old-key" }, errors: instance_double(ActiveModel::Errors, full_messages: []))
      allow(config).to receive(:is_active=)
      allow(config).to receive(:settings=)
      allow(config).to receive(:save).and_return(true)
      allow(CdnConfiguration).to receive(:find_or_initialize_by).with(provider: "fastly").and_return(config)
      allow_any_instance_of(Api::V1::CdnConfigurationsController).to receive(:params).and_return(
        ActiveSupport::HashWithIndifferentAccess.new(provider: "fastly", is_active: false)
      )

      put api_v1_cdn_configurations_path,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(config).to have_received(:settings=).with("api_key" => "old-key")
    end

    it "accepts a valid image_optimizer_formats allow-list (webp and avif)" do
      sign_in admin
      config = instance_double(CdnConfiguration, settings: {}, errors: instance_double(ActiveModel::Errors, full_messages: []))
      allow(config).to receive(:is_active=)
      allow(config).to receive(:settings=)
      allow(config).to receive(:save).and_return(true)
      allow(CdnConfiguration).to receive(:find_or_initialize_by).with(provider: "fastly").and_return(config)

      put api_v1_cdn_configurations_path,
          params: { provider: "fastly", is_active: true, settings: { image_optimizer_formats: [ "webp", "avif" ] } },
          as: :json

      expect(response).to have_http_status(:ok)
      expect(config).to have_received(:settings=).with("image_optimizer_formats" => [ "webp", "avif" ])
    end

    it "rejects an unsupported image optimizer format" do
      sign_in admin
      config = instance_double(CdnConfiguration, settings: {})
      allow(config).to receive(:is_active=)
      allow(CdnConfiguration).to receive(:find_or_initialize_by).with(provider: "fastly").and_return(config)
      expect(config).not_to receive(:settings=)

      put api_v1_cdn_configurations_path,
          params: { provider: "fastly", is_active: true, settings: { image_optimizer_formats: [ "webp", "jxl" ] } },
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].first).to include("jxl")
    end
  end
end
