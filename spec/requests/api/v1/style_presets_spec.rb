# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::StylePresets", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:member)  { create(:user) }
  let(:headers) { { "Content-Type" => "application/json", "Accept" => "application/json" } }

  def auth_headers(user)
    sign_in user
    headers
  end

  describe "GET /api/v1/style_presets" do
    before { create_list(:style_preset, 3) }

    context "as admin" do
      it "returns all presets" do
        get "/api/v1/style_presets", headers: auth_headers(admin)
        expect(response).to have_http_status(:ok)
        expect(json["total"]).to eq(3)
        expect(json["presets"].length).to eq(3)
      end

      it "includes stale and synced flags" do
        get "/api/v1/style_presets", headers: auth_headers(admin)
        expect(json["presets"].first).to have_key("stale")
        expect(json["presets"].first).to have_key("synced_at")
      end
    end

    context "as non-admin" do
      it "returns 403" do
        get "/api/v1/style_presets", headers: auth_headers(member)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/style_presets" do
    let(:valid_params) do
      { style_preset: {
          name: "Editorial Dark",
          description: "Dark editorial style",
          style_params: { "tone" => "dark", "palette" => [ "#000000", "#333333" ] },
        } }
    end

    it "creates a style preset with derived slug" do
      expect {
        post "/api/v1/style_presets", params: valid_params.to_json, headers: auth_headers(admin)
      }.to change(StylePreset, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json["slug"]).to eq("editorial-dark")
      expect(json["created_by"]).to eq(admin.email)
    end

    it "returns 422 for missing name" do
      post "/api/v1/style_presets", params: { style_preset: { description: "no name" } }.to_json,
           headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/style_presets/:id" do
    let!(:preset) { create(:style_preset) }

    it "updates the preset" do
      patch "/api/v1/style_presets/#{preset.id}",
            params: { style_preset: { description: "Updated description" } }.to_json,
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["description"]).to eq("Updated description")
    end
  end

  describe "DELETE /api/v1/style_presets/:id" do
    let!(:preset) { create(:style_preset) }

    it "deletes the preset" do
      expect {
        delete "/api/v1/style_presets/#{preset.id}", headers: auth_headers(admin)
      }.to change(StylePreset, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/style_presets/:id/sync" do
    let!(:preset) { create(:style_preset) }

    it "enqueues a sync worker" do
      expect(StylePresetSyncWorker).to receive(:perform_async).with(preset.id)
      post "/api/v1/style_presets/#{preset.id}/sync", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/style_presets/:id/set_default" do
    let!(:existing_default) { create(:style_preset, :default) }
    let!(:preset)           { create(:style_preset) }

    it "promotes preset to default and demotes previous" do
      post "/api/v1/style_presets/#{preset.id}/set_default", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["is_default"]).to be true
      expect(existing_default.reload.is_default).to be false
    end
  end

  describe "GET /api/v1/style_presets/:id — not found" do
    it "returns 404" do
      get "/api/v1/style_presets/999999", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  private

  def json
    JSON.parse(response.body)
  end
end
