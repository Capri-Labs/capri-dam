# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Entities", type: :request do
  let(:user) { create(:user, admin: true) }

  def json = response.parsed_body

  before { sign_in user }

  describe "GET /api/v1/entities/vocabulary" do
    it "serves the type/relationship matrix so no client has to hardcode it" do
      get "/api/v1/entities/vocabulary", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["entity_types"]).to match_array(Entity::TYPES)

      shot_by = json["relationships"].find { |r| r["name"] == "shot_by" }
      expect(shot_by["entity_types"]).to eq([ "person" ])
    end
  end

  describe "GET /api/v1/entities" do
    it "filters by type and finds entities by alias as well as name" do
      brand = create(:entity, :brand, name: "Volkswagen")
      create(:entity_alias, entity: brand, alias_text: "vw")
      create(:entity, :place, name: "Wolfsburg")

      get "/api/v1/entities", params: { entity_type: "brand", q: "VW" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["entities"].map { |e| e["name"] }).to eq([ "Volkswagen" ])
      expect(json["entities"].first["reference"]).to eq("brand:volkswagen")
    end

    it "hides entities that were merged away" do
      survivor = create(:entity, :brand, name: "Volkswagen")
      create(:entity, :brand, name: "VW", canonical: survivor)

      get "/api/v1/entities", as: :json

      expect(json["entities"].map { |e| e["name"] }).to eq([ "Volkswagen" ])
    end

    it "caps the page size however large a limit is requested" do
      create_list(:entity, 3, entity_type: "place")

      get "/api/v1/entities", params: { limit: 5000 }, as: :json

      expect(json["entities"].size).to eq(3)
    end

    it "requires authentication" do
      sign_out user

      get "/api/v1/entities", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/entities" do
    it "creates an entity with aliases" do
      post "/api/v1/entities", params: {
        entity: { entity_type: "brand", name: "Volkswagen" },
        aliases: [ "VW", "Volkswagen AG" ],
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["slug"]).to eq("volkswagen")
      expect(json["aliases"].map { |a| a["alias_text"] }).to contain_exactly("vw", "volkswagen ag")
    end

    it "lets the same name exist under two types" do
      create(:entity, :place, name: "Berlin")

      post "/api/v1/entities", params: { entity: { entity_type: "person", name: "Berlin" } }, as: :json

      expect(response).to have_http_status(:created)
    end

    it "rejects a duplicate within one type" do
      create(:entity, :place, name: "Berlin")

      post "/api/v1/entities", params: { entity: { entity_type: "place", name: "Berlin" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"].join).to match(/already used/)
    end
  end

  describe "PATCH /api/v1/entities/:id" do
    it "ignores an attempt to change the type, which would invalidate every link" do
      entity = create(:entity, :place, name: "Berlin")

      patch "/api/v1/entities/#{entity.id}",
            params: { entity: { name: "Berlin, DE", entity_type: "campaign" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(entity.reload.name).to eq("Berlin, DE")
      expect(entity.entity_type).to eq("place")
    end
  end

  describe "DELETE /api/v1/entities/:id" do
    it "deletes an entity nobody linked to" do
      entity = create(:entity, :place)

      delete "/api/v1/entities/#{entity.id}", as: :json

      expect(response).to have_http_status(:no_content)
    end

    it "refuses while links exist, and points at merge instead" do
      entity = create(:entity, :place)
      create(:asset_entity, entity: entity, relationship: "located_at")

      delete "/api/v1/entities/#{entity.id}", as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to match(/Merge it into another entity/)
      expect(entity.reload).to be_persisted
    end
  end

  describe "POST /api/v1/entities/:id/merge" do
    it "folds the duplicate into the survivor and moves its links" do
      survivor = create(:entity, :brand, name: "Volkswagen")
      duplicate = create(:entity, :brand, name: "VW")
      link = create(:asset_entity, entity: duplicate, relationship: "depicts")

      post "/api/v1/entities/#{duplicate.id}/merge", params: { canonical_id: survivor.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["links_moved"]).to eq(1)
      expect(link.reload.entity).to eq(survivor)
      expect(duplicate.reload.canonical_id).to eq(survivor.id)
    end

    it "refuses a cross-type merge" do
      survivor = create(:entity, :brand, name: "Volkswagen")
      place = create(:entity, :place, name: "Wolfsburg")

      post "/api/v1/entities/#{place.id}/merge", params: { canonical_id: survivor.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to match(/Cannot merge a place into a brand/)
    end

    it "404s for an unknown target" do
      duplicate = create(:entity, :brand)

      post "/api/v1/entities/#{duplicate.id}/merge", params: { canonical_id: SecureRandom.uuid }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "aliases" do
    let(:entity) { create(:entity, :brand, name: "Volkswagen") }

    it "adds one, normalised" do
      post "/api/v1/entities/#{entity.id}/aliases", params: { alias_text: "  VW  " }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["aliases"].map { |a| a["alias_text"] }).to eq([ "vw" ])
    end

    it "rejects the same alias twice on one entity" do
      create(:entity_alias, entity: entity, alias_text: "vw")

      post "/api/v1/entities/#{entity.id}/aliases", params: { alias_text: "VW" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "allows the same alias on two different entities, because that ambiguity is real" do
      create(:entity_alias, entity: entity, alias_text: "berlin")
      other = create(:entity, :place, name: "Berlin DE")

      post "/api/v1/entities/#{other.id}/aliases", params: { alias_text: "berlin" }, as: :json

      expect(response).to have_http_status(:created)
    end

    it "removes one" do
      record = create(:entity_alias, entity: entity, alias_text: "vw")

      delete "/api/v1/entities/#{entity.id}/aliases/#{record.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["aliases"]).to be_empty
    end
  end
end
