# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::AssetDownloads', type: :request do
  # ── POST /api/v1/asset_downloads ─────────────────────────────────────────────
  path '/api/v1/asset_downloads' do
    post 'Bundle one or more folders and/or assets into a ZIP for download' do
      tags        'Asset Downloads'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Bulk "Download" endpoint backing the Explorer Tools-menu Download
        overlay — the asynchronous ZIP counterpart to individual asset/
        rendition downloads (which already work via
        `GET /api/v1/assets/local/:uuid`).

        Building the archive can be slow for large selections, so this
        endpoint only validates the request and enqueues
        `AssetDownloadWorker` — it responds immediately with `202 Accepted`
        and a `pending` record the client polls via
        `GET /api/v1/asset_downloads/:id` to drive a progress bar.

        Only `:read` on each item's folder is required (nothing is mutated).
        Items the requesting user can't read are dropped with a per-item
        entry in `errors`, but the request still succeeds for the rest of
        the selection. `total_items` is the *real*, recursively-expanded
        file count (folders are walked up front) so the progress bar has an
        accurate denominator from the first poll.

        `queued` is `true` when the user already has another pending/
        processing download — the UI uses this to immediately tell them
        their new request has been queued behind it, since Sidekiq
        processes same-queue jobs roughly in order.

        Once the worker finishes, the user is notified via both their
        notification bell and inbox with a direct link to
        `GET /api/v1/asset_downloads/:id/download`.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          folder_ids: {
            type: :array, items: { type: :integer },
            description: 'IDs of folders to bundle (expanded recursively)',
            example: [ 12, 13 ]
          },
          asset_ids: {
            type: :array, items: { type: :integer },
            description: 'IDs of assets to bundle',
            example: [ 101 ]
          },
          name: {
            type: :string,
            description: 'Display name / ZIP filename stem; auto-generated when omitted',
            example: 'Q3 Marketing Assets',
          },
        },
      }

      response '202', 'download queued (fully or partially)' do
        schema type: :object,
               properties: {
                 id: { type: :integer, example: 1 },
                 name: { type: :string, example: 'Q3 Marketing Assets' },
                 status: { type: :string, enum: %w[pending processing completed failed], example: 'pending' },
                 total_items: { type: :integer, example: 3 },
                 processed_items: { type: :integer, example: 0 },
                 progress_percent: { type: :integer, example: 0 },
                 file_count: { type: :integer, example: 0 },
                 byte_size: { type: :integer, example: 0 },
                 error_message: { type: :string, nullable: true },
                 created_at: { type: :string },
                 expires_at: { type: :string, nullable: true },
                 download_url: { type: :string, nullable: true },
                 queued: { type: :boolean, example: false },
                 errors: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       type: { type: :string, enum: %w[folder asset] },
                       id: { type: :integer },
                       name: { type: :string, nullable: true },
                       error: { type: :string },
                     },
                   },
                 },
               }
        run_test!
      end

      response '422', 'no folders or assets were specified' do
        schema type: :object, properties: { error: { type: :string, example: 'No folders or assets were specified.' } }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end
    end
  end

  # ── GET /api/v1/asset_downloads ──────────────────────────────────────────────
  path '/api/v1/asset_downloads' do
    get "List the current user's downloads" do
      tags     'Asset Downloads'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Non-expired downloads for the current user, most recent first — used by the reuse/history table.'

      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false, description: '10, 25, or 50 (default 25)'

      response '200', 'downloads listed' do
        schema type: :object,
               properties: {
                 downloads: { type: :array, items: { type: :object } },
                 meta: {
                   type: :object,
                   properties: {
                     total: { type: :integer }, page: { type: :integer }, per_page: { type: :integer }
                   },
                 },
               }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end
    end
  end

  # ── GET /api/v1/asset_downloads/:id ───────────────────────────────────────────
  path '/api/v1/asset_downloads/{id}' do
    get 'Poll a single download\'s progress/status' do
      tags     'Asset Downloads'
      produces 'application/json'
      security [ Bearer: [] ]
      parameter name: :id, in: :path, type: :integer

      response '200', 'download found' do
        let(:id) { 1 }
        schema type: :object, properties: { id: { type: :integer }, status: { type: :string } }
        run_test!
      end

      response '404', 'not found / not owned by the current user' do
        let(:id) { 0 }
        run_test!
      end
    end

    delete 'Delete a download and purge its ZIP' do
      tags     'Asset Downloads'
      produces 'application/json'
      security [ Bearer: [] ]
      parameter name: :id, in: :path, type: :integer

      response '200', 'deleted' do
        let(:id) { 1 }
        schema type: :object, properties: { success: { type: :boolean, example: true } }
        run_test!
      end

      response '404', 'not found / not owned by the current user' do
        let(:id) { 0 }
        run_test!
      end
    end
  end

  # ── GET /api/v1/asset_downloads/:id/download ─────────────────────────────────
  path '/api/v1/asset_downloads/{id}/download' do
    get 'Download the finished ZIP' do
      tags     'Asset Downloads'
      security [ Bearer: [] ]
      parameter name: :id, in: :path, type: :integer
      description 'Redirects to the attached ZIP blob. Returns 404 until the download has completed.'

      response '302', 'redirects to the ZIP blob' do
        let(:id) { 1 }
        run_test!
      end

      response '404', 'not ready or file missing' do
        let(:id) { 1 }
        run_test!
      end
    end
  end
end
