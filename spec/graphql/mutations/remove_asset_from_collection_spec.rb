# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL removeAssetFromCollection", type: :request do
  let(:user) { create(:user) }
  let(:mutation) do
    <<~GQL
      mutation($input: RemoveAssetFromCollectionInput!) {
        removeAssetFromCollection(input: $input) {
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

    expect(result.dig("data", "removeAssetFromCollection", "collection")).to be_nil
    expect(result.dig("data", "removeAssetFromCollection", "errors")).to eq([ "Collection not found" ])
  end

  it "returns an error when the asset is not in the collection" do
    collection = create(:collection)
    asset = create(:asset)

    result = gql(variables: { input: { collectionId: collection.id, assetId: asset.id } })

    expect(result.dig("data", "removeAssetFromCollection", "collection", "id").to_i).to eq(collection.id)
    expect(result.dig("data", "removeAssetFromCollection", "errors")).to eq([ "Asset is not in this collection" ])
  end
end
