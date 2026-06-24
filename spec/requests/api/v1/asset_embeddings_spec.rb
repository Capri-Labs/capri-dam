# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::AssetEmbeddings', type: :request do

  # ===========================================================================
  # PUT /api/v1/assets/{asset_id}/embedding
  # ===========================================================================
  path '/api/v1/assets/{asset_id}/embedding' do

    put 'Upsert the AI vector embedding for an asset' do
      tags        'Asset Embeddings'
      consumes    'application/json'
      produces    'application/json'
      security    [Bearer: []]
      description <<~DESC
        Stores or overwrites the AI-generated vector embedding associated with a specific asset.
        Called by the internal AI microservice (embedding pipeline) after analysing asset content.
        Uses an upsert strategy — if an embedding already exists it is overwritten rather than duplicated.
      DESC

      parameter name: :asset_id, in: :path, type: :string, required: true,
                description: 'UUID of the target asset'

      parameter name: :body, in: :body, required: true,
                schema: {
                  type: :object,
                  required: [:asset_embedding],
                  properties: {
                    asset_embedding: {
                      type: :object,
                      required: [:embedding, :model_name],
                      properties: {
                        embedding: {
                          type:        :array,
                          items:       { type: :number, format: :float },
                          description: 'Dense vector produced by the embedding model (e.g. 1536-dim for OpenAI text-embedding-3-small)',
                          example:     [0.021, -0.034, 0.018]
                        },
                        model_name: {
                          type:        :string,
                          description: 'Identifier of the model that produced the embedding',
                          example:     'text-embedding-3-small'
                        }
                      }
                    }
                  }
                }

      # ── 200 OK ─────────────────────────────────────────────────────────────
      response '200', 'Vector spatial index updated' do
        schema type: :object,
               properties: {
                 message: { type: :string, example: 'Vector spatial index updated' }
               },
               required: [:message]

        let(:asset_id) { create(:asset).id }
        let(:body) do
          {
            asset_embedding: {
              embedding:  Array.new(8) { rand(-1.0..1.0).round(6) },
              model_name: 'text-embedding-3-small'
            }
          }
        end

        run_test!
      end

      # ── 422 Unprocessable Entity ────────────────────────────────────────────
      response '422', 'Validation failed — embedding payload is invalid' do
        schema type: :object,
               properties: {
                 errors: { type: :array, items: { type: :string }, example: ["Embedding can't be blank"] }
               },
               required: [:errors]

        let(:asset_id) { create(:asset).id }
        let(:body) do
          {
            asset_embedding: {
              embedding:  nil,
              model_name: ''
            }
          }
        end

        run_test!
      end

      # ── 404 Not Found ───────────────────────────────────────────────────────
      response '404', 'Asset not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Record not found' }
               }

        let(:asset_id) { 'non-existent-uuid' }
        let(:body) do
          {
            asset_embedding: {
              embedding:  [0.1, 0.2],
              model_name: 'text-embedding-3-small'
            }
          }
        end

        run_test!
      end
    end
  end
end

