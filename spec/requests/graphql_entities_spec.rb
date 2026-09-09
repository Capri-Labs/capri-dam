# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL entity graph queries", type: :request do
  let(:user) { create(:user) }

  def gql_post(query:, user:)
    sign_in(user)
    post "/graphql", params: { query: query }.to_json,
                     headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    JSON.parse(response.body)
  end

  # ---------------------------------------------------------------------------
  # entities
  # ---------------------------------------------------------------------------

  describe "entities query" do
    let!(:person) { create(:entity, entity_type: "person", name: "Jane Doe") }
    let!(:place)  { create(:entity, entity_type: "place",  name: "Berlin") }

    it "lists entities with a server-built search reference" do
      body = gql_post(query: "{ entities { name reference entityType } }", user: user)

      expect(body["errors"]).to be_nil
      names = body.dig("data", "entities").map { |e| e["name"] }
      expect(names).to contain_exactly("Jane Doe", "Berlin")
      expect(body.dig("data", "entities").find { |e| e["name"] == "Berlin" }["reference"])
        .to eq("place:berlin")
    end

    it "filters by type" do
      body = gql_post(query: '{ entities(entityType: "place") { name } }', user: user)

      expect(body.dig("data", "entities").map { |e| e["name"] }).to eq([ "Berlin" ])
    end

    it "matches on an alias, not only the canonical name" do
      create(:entity_alias, entity: person, alias_text: "j doe")

      body = gql_post(query: '{ entities(query: "j doe") { name } }', user: user)

      expect(body.dig("data", "entities").map { |e| e["name"] }).to eq([ "Jane Doe" ])
    end

    it "excludes entities that have been merged away" do
      duplicate = create(:entity, entity_type: "person", name: "Jane D.")
      duplicate.update!(canonical_id: person.id)

      body = gql_post(query: "{ entities { name } }", user: user)

      expect(body.dig("data", "entities").map { |e| e["name"] }).not_to include("Jane D.")
    end

    it "is not reachable anonymously" do
      post "/graphql", params: { query: "{ entities { name } }" }.to_json,
                       headers: { "Content-Type" => "application/json" }

      expect(response).not_to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # entity
  # ---------------------------------------------------------------------------

  describe "entity query" do
    let!(:person) { create(:entity, entity_type: "person", name: "Jane Doe") }

    it "resolves a type:slug reference" do
      body = gql_post(query: '{ entity(reference: "person:jane-doe") { name aliases } }', user: user)

      expect(body.dig("data", "entity", "name")).to eq("Jane Doe")
    end

    it "resolves a UUID" do
      body = gql_post(query: %({ entity(reference: "#{person.id}") { name } }), user: user)

      expect(body.dig("data", "entity", "name")).to eq("Jane Doe")
    end

    it "follows a merge so an old reference does not rot" do
      duplicate = create(:entity, entity_type: "person", name: "Jane D.")
      duplicate.update!(canonical_id: person.id)

      body = gql_post(query: '{ entity(reference: "person:jane-d") { name } }', user: user)

      expect(body.dig("data", "entity", "name")).to eq("Jane Doe")
    end

    it "returns null for an unknown reference" do
      body = gql_post(query: '{ entity(reference: "person:nobody") { name } }', user: user)

      expect(body.dig("data", "entity")).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # asset.entityLinks
  # ---------------------------------------------------------------------------

  describe "entityLinks on an asset" do
    let(:asset)  { create(:asset) }
    let(:person) { create(:entity, entity_type: "person", name: "Jane Doe") }
    let(:place)  { create(:entity, entity_type: "place",  name: "Berlin") }

    let(:query) do
      <<~GQL
        { assetDetail(uuid: "%{uuid}") { entityLinks { relationship source asserted entity { name } } } }
      GQL
    end

    before do
      create(:asset_entity, asset: asset, entity: person, relationship: "shot_by")
      create(:asset_entity, :from_tag, asset: asset, entity: place, relationship: "located_at")
    end

    it "returns the relationship, not just the entity" do
      body = gql_post(query: format(query, uuid: asset.uuid), user: user)

      links = body.dig("data", "assetDetail", "entityLinks")
      expect(links.map { |l| l["relationship"] }).to contain_exactly("shot_by", "located_at")
      expect(links.find { |l| l["relationship"] == "shot_by" }["entity"]["name"]).to eq("Jane Doe")
    end

    it "reports an unconfirmed proposal as not asserted" do
      body = gql_post(query: format(query, uuid: asset.uuid), user: user)

      links = body.dig("data", "assetDetail", "entityLinks")
      expect(links.find { |l| l["source"] == "tag_resolution" }["asserted"]).to be(false)
      expect(links.find { |l| l["source"] == "manual" }["asserted"]).to be(true)
    end

    it "hides unconfirmed proposals when assertedOnly is set" do
      asserted_query = <<~GQL
        { assetDetail(uuid: "%{uuid}") { entityLinks(assertedOnly: true) { relationship } } }
      GQL

      body = gql_post(query: format(asserted_query, uuid: asset.uuid), user: user)

      links = body.dig("data", "assetDetail", "entityLinks")
      expect(links.map { |l| l["relationship"] }).to eq([ "shot_by" ])
    end

    it "filters by relationship" do
      filtered = <<~GQL
        { assetDetail(uuid: "%{uuid}") { entityLinks(relationship: "located_at") { entity { name } } } }
      GQL

      body = gql_post(query: format(filtered, uuid: asset.uuid), user: user)

      links = body.dig("data", "assetDetail", "entityLinks")
      expect(links.map { |l| l.dig("entity", "name") }).to eq([ "Berlin" ])
    end
  end
end
