# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::EdgeOperations', type: :request do
  # ── POST /api/v1/edge_operations/sync ────────────────────────────────────────
  path '/api/v1/edge_operations/sync' do
    post 'Sync metadata to Edge KV for selected folders and assets' do
      tags        'Edge CDN Operations'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Dispatches `FolderMetadataSyncWorker` (per folder) and `EdgeMetadataSyncWorker`
        (per asset) to push fresh JSON metadata to the Cloudflare / CDN edge KV store.

        Call this after bulk metadata updates to ensure edge nodes serve current data
        without waiting for the next cache TTL expiry.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          folders: {
            type: :array, items: { type: :string },
            description: 'Folder IDs (UUID strings) to sync',
            example: [ 'abc123', 'def456' ]
          },
          assets: {
            type: :array, items: { type: :string },
            description: 'Asset UUIDs to sync',
            example: [ '3fa85f64-5717-4562-b3fc-2c963f66afa6' ]
          },
        },
      }

      response '202', 'sync workers enqueued' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Metadata sync initiated for 2 folders and 1 assets.' },
               }
        run_test!
      end
    end
  end

  # ── POST /api/v1/edge_operations/purge ───────────────────────────────────────
  path '/api/v1/edge_operations/purge' do
    post 'Purge CDN edge cache for selected folders and assets' do
      tags        'Edge CDN Operations'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Dispatches `CdnInvalidationWorker` to invalidate cache tags at the delivery
        edge for each supplied folder or asset UUID. After purge, the next request
        for those URLs fetches fresh content from origin.

        Use this after publishing new asset versions, updating metadata, or moving
        assets between folders.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          folders: {
            type: :array, items: { type: :string },
            description: 'Folder IDs whose cache tags should be invalidated',
            example: [ 'abc123' ]
          },
          assets: {
            type: :array, items: { type: :string },
            description: 'Asset UUIDs whose delivery URLs should be purged',
            example: [ '3fa85f64-5717-4562-b3fc-2c963f66afa6' ]
          },
        },
      }

      response '202', 'purge workers enqueued' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Cache purge initiated for 1 folders and 1 assets.' },
               }
        run_test!
      end
    end
  end
end
