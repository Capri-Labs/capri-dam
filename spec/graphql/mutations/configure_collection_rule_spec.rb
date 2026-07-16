# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL configureCollectionRule", type: :request do
  let(:user) { create(:user, :admin) }
  let(:mutation) do
    <<~GQL
      mutation($input: ConfigureCollectionRuleInput!) {
        configureCollectionRule(input: $input) {
          collection {
            id
            collectionRule { matchMode semanticPrompt metadataFilters active }
          }
          errors
        }
      }
    GQL
  end

  def gql(variables:)
    post "/graphql", params: { query: mutation, variables: variables }, as: :json
    JSON.parse(response.body)
  end

  before { sign_in user }

  it "returns an error when the collection cannot be found" do
    result = gql(variables: { input: { collectionId: 0, semanticPrompt: "beach photos" } })

    expect(result.dig("data", "configureCollectionRule", "collection")).to be_nil
    expect(result.dig("data", "configureCollectionRule", "errors")).to eq([ "Collection not found" ])
  end

  it "creates a semantic rule and marks the collection as smart" do
    collection = create(:collection, user: user)

    result = gql(variables: { input: { collectionId: collection.id, semanticPrompt: "beach photos" } })

    rule = result.dig("data", "configureCollectionRule", "collection", "collectionRule")
    expect(rule["matchMode"]).to eq("semantic")
    expect(rule["semanticPrompt"]).to eq("beach photos")
    expect(collection.reload).to be_smart
  end

  it "creates a metadata-only rule without requiring a semantic prompt" do
    collection = create(:collection, user: user)

    result = gql(variables: {
      input: { collectionId: collection.id, matchMode: "metadata", metadataFilters: { status: "approved" } },
    })

    rule = result.dig("data", "configureCollectionRule", "collection", "collectionRule")
    expect(rule["matchMode"]).to eq("metadata")
    expect(rule["metadataFilters"]).to eq("status" => "approved")
  end

  it "surfaces validation errors" do
    collection = create(:collection, user: user)

    result = gql(variables: { input: { collectionId: collection.id, semanticPrompt: "" } })

    expect(result.dig("data", "configureCollectionRule", "collection")).to be_nil
    expect(result.dig("data", "configureCollectionRule", "errors")).to include("Semantic prompt can't be blank")
  end

  context "when the caller lacks administrative access to the workspace" do
    let(:user) { create(:user, admin: false) }

    it "denies the mutation" do
      owner = create(:user, admin: false)
      collection = create(:collection, user: owner)

      result = gql(variables: { input: { collectionId: collection.id, semanticPrompt: "beach photos" } })

      expect(result.dig("data", "configureCollectionRule", "collection")).to be_nil
      expect(result.dig("data", "configureCollectionRule", "errors")).to eq(
        [ "You do not have administrative access to this workspace." ]
      )
    end
  end
end
