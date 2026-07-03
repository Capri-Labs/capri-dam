# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL addAssetToCollection", type: :request do
  let(:user) { create(:user) }
  let(:mutation) do
    <<~GQL
      mutation($input: AddAssetToCollectionInput!) {
        addAssetToCollection(input: $input) {
          collection { id }
          errors
        }
      }
    GQL
  end

  def gql(variables:)
    sign_in user
    post "/graphql", params: { query: mutation, variables: variables }, as: :json
    JSON.parse(response.body)
  end

  it "returns an error when the collection cannot be found" do
    asset = create(:asset)

    result = gql(variables: { input: { collectionId: 0, assetId: asset.id } })

    expect(result.dig("data", "addAssetToCollection", "collection")).to be_nil
    expect(result.dig("data", "addAssetToCollection", "errors")).to eq([ "Collection not found" ])
  end

  it "returns an error when the asset cannot be found" do
    collection = create(:collection)

    result = gql(variables: { input: { collectionId: collection.id, assetId: 0 } })

    expect(result.dig("data", "addAssetToCollection", "collection")).to be_nil
    expect(result.dig("data", "addAssetToCollection", "errors")).to eq([ "Asset not found" ])
  end

  it "returns validation errors when the asset is already in the collection" do
    collection = create(:collection)
    asset = create(:asset)
    create(:collection_asset, collection: collection, asset: asset)

    result = gql(variables: { input: { collectionId: collection.id, assetId: asset.id } })

    expect(result.dig("data", "addAssetToCollection", "collection")).to be_nil
    expect(result.dig("data", "addAssetToCollection", "errors")).to include("Asset is already in this collection")
  end
end
