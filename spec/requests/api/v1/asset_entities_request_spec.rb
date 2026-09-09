# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AssetEntities", type: :request do
  let(:user)  { create(:user, admin: true) }
  let(:asset) { create(:asset) }

  def json = response.parsed_body

  before { sign_in user }

  describe "GET /api/v1/assets/:asset_id/entities" do
    it "lists the links and says which are asserted" do
      person = create(:entity, :person, name: "Jane Doe")
      create(:asset_entity, asset: asset, entity: person, relationship: "shot_by")
      create(:asset_entity, :from_ai, asset: asset, entity: create(:entity, :product, name: "Runner"),
                                      relationship: "depicts")

      get "/api/v1/assets/#{asset.id}/entities", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["links"].map { |l| l["asserted"] }).to contain_exactly(true, false)
      expect(json["links"].map { |l| l["entity"]["reference"] })
        .to include("person:jane-doe", "product:runner")
    end

    it "resolves the asset by uuid as well as id" do
      get "/api/v1/assets/#{asset.uuid}/entities", as: :json

      expect(response).to have_http_status(:ok)
    end

    it "requires authentication" do
      sign_out user

      get "/api/v1/assets/#{asset.id}/entities", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/assets/:asset_id/entities" do
    it "creates an asserted link" do
      person = create(:entity, :person, name: "Jane Doe")

      post "/api/v1/assets/#{asset.id}/entities",
           params: { entity_id: person.id, relationship: "shot_by" }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["asserted"]).to be(true)
      expect(json["source"]).to eq("manual")
      expect(json["confirmed_by"]).to eq(user.email)
    end

    it "refuses a relationship the entity type cannot hold" do
      campaign = create(:entity, :campaign, name: "Spring")

      post "/api/v1/assets/#{asset.id}/entities",
           params: { entity_id: campaign.id, relationship: "shot_by" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to match(/cannot point at a campaign/)
    end

    it "links to the survivor when asked to link to a merged-away duplicate" do
      survivor = create(:entity, :brand, name: "Volkswagen")
      duplicate = create(:entity, :brand, name: "VW", canonical: survivor)

      post "/api/v1/assets/#{asset.id}/entities",
           params: { entity_id: duplicate.id, relationship: "depicts" }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["entity"]["id"]).to eq(survivor.id)
    end

    it "404s for an unknown entity" do
      post "/api/v1/assets/#{asset.id}/entities",
           params: { entity_id: SecureRandom.uuid, relationship: "depicts" }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/assets/:asset_id/entities/resolve" do
    let(:asset) { create(:asset, properties: { "tags" => [ "berlin", "sunset" ] }) }

    it "links unambiguous tags and reports the rest" do
      create(:entity, :place, name: "Berlin")

      post "/api/v1/assets/#{asset.id}/entities/resolve", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["linked"].first).to include("tag" => "berlin", "relationship" => "located_at")
      expect(json["unmatched"]).to eq([ "sunset" ])
    end

    it "reports ambiguity with its candidates instead of choosing" do
      create(:entity, :place, name: "Berlin")
      create(:entity, :person, name: "Berlin")

      post "/api/v1/assets/#{asset.id}/entities/resolve", as: :json

      expect(json["linked"]).to be_empty
      expect(json["ambiguous"].first["candidates"].map { |c| c["entity_type"] })
        .to contain_exactly("place", "person")
      expect(asset.asset_entities).to be_empty
    end

    it "writes nothing on a dry run" do
      create(:entity, :place, name: "Berlin")

      post "/api/v1/assets/#{asset.id}/entities/resolve", params: { dry_run: true }, as: :json

      expect(json["dry_run"]).to be(true)
      expect(json["linked"].size).to eq(1)
      expect(AssetEntity.count).to eq(0)
    end

    it "leaves the asset's tags untouched" do
      create(:entity, :place, name: "Berlin")

      expect { post "/api/v1/assets/#{asset.id}/entities/resolve", as: :json }
        .not_to change { asset.reload.properties["tags"] }
    end
  end

  describe "POST /api/v1/asset_entities/:id/confirm" do
    it "turns a proposal into an assertion" do
      link = create(:asset_entity, :from_ai, asset: asset)

      post "/api/v1/asset_entities/#{link.id}/confirm", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["asserted"]).to be(true)
      expect(json["confirmed_by"]).to eq(user.email)
      expect(link.reload.source).to eq("ai")
    end

    it "404s for an unknown link" do
      post "/api/v1/asset_entities/#{SecureRandom.uuid}/confirm", as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/asset_entities/:id" do
    it "removes the link but never the entity" do
      entity = create(:entity, :person)
      link = create(:asset_entity, asset: asset, entity: entity)

      delete "/api/v1/asset_entities/#{link.id}", as: :json

      expect(response).to have_http_status(:no_content)
      expect(AssetEntity.exists?(link.id)).to be(false)
      expect(entity.reload).to be_persisted
    end
  end
end
