# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AssetEmbeddings coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let(:asset) { create(:asset, user: user) }
  let(:embedding) { Array.new(1536, 0.001) }

  before do
    sign_in admin
    allow(Redis).to receive(:new).and_return(instance_double(Redis, publish: true))
    allow(SmartCollectionRouterWorker).to receive(:perform_async)
  end

  it "creates an embedding for an asset" do
    expect {
      put "/api/v1/assets/#{asset.id}/embedding", params: {
        asset_embedding: { embedding: embedding, model_name: "text-embedding-3-small" },
      }, as: :json
    }.to change(AssetEmbedding, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["message"]).to eq("Vector spatial index updated")
    expect(asset.reload.asset_embedding.model_name).to eq("text-embedding-3-small")
  end

  it "updates an existing embedding instead of duplicating it" do
    asset.create_asset_embedding!(embedding: embedding, model_name: "old-model")

    expect {
      patch "/api/v1/assets/#{asset.id}/embedding", params: {
        asset_embedding: { embedding: Array.new(1536, 0.002), model_name: "new-model" },
      }, as: :json
    }.not_to change(AssetEmbedding, :count)

    expect(response).to have_http_status(:ok)
    expect(asset.reload.asset_embedding.model_name).to eq("new-model")
  end

  it "returns validation errors for invalid embedding payloads" do
    validation_errors = instance_double(ActiveModel::Errors, full_messages: [ "Embedding can't be blank" ])
    allow_any_instance_of(AssetEmbedding).to receive(:save).and_return(false)
    allow_any_instance_of(AssetEmbedding).to receive(:errors).and_return(validation_errors)

    put "/api/v1/assets/#{asset.id}/embedding", params: {
      asset_embedding: { embedding: [], model_name: "" },
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["errors"]).to eq([ "Embedding can't be blank" ])
  end

  it "returns 404 for a missing asset" do
    put "/api/v1/assets/#{SecureRandom.uuid}/embedding", params: {
      asset_embedding: { embedding: embedding, model_name: "text-embedding-3-small" },
    }, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "forbids non-admin users" do
    sign_out admin
    sign_in user

    put "/api/v1/assets/#{asset.id}/embedding", params: {
      asset_embedding: { embedding: embedding, model_name: "text-embedding-3-small" },
    }, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "returns 401 when unauthenticated" do
    sign_out admin

    put "/api/v1/assets/#{asset.id}/embedding", params: {
      asset_embedding: { embedding: embedding, model_name: "text-embedding-3-small" },
    }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
