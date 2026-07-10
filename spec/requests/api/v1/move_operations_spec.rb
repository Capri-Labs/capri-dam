# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::MoveOperations', type: :request do
  # ── POST /api/v1/move_operations ─────────────────────────────────────────────
  path '/api/v1/move_operations' do
    post 'Move one or more folders and/or assets to a destination folder' do
      tags        'Move'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Bulk "Move" endpoint backing the Explorer Tools-menu Move overlay.

        Moving is modelled as removing an item from its current folder and adding
        it to a destination folder, so it is gated by two permission checks:

        * `:delete` on the item's *current* parent folder
        * `:create` on the *destination* folder

        A `nil`/`"root"` folder always passes both checks (no policy applies at
        the root). Admins bypass all checks.

        Each folder/asset is evaluated independently, so one item failing
        permission or validation (e.g. a name collision, or a folder move that
        would create a cycle) does not abort the rest of the batch — the
        response reports per-item errors alongside the overall success counts.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          folder_ids: {
            type: :array, items: { type: :integer },
            description: 'IDs of folders to move',
            example: [ 12, 13 ]
          },
          asset_ids: {
            type: :array, items: { type: :integer },
            description: 'IDs of assets to move',
            example: [ 101 ]
          },
          destination_folder_id: {
            type: :string,
            description: 'Destination folder ID, or "root" (or omitted/blank) to move to the top level',
            example: '42',
          },
        },
      }

      response '200', 'move completed (fully or partially)' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 moved_folders: { type: :integer, example: 2 },
                 moved_assets: { type: :integer, example: 1 },
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

      response '404', 'destination folder not found' do
        schema type: :object, properties: { error: { type: :string, example: 'Destination folder not found.' } }
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
end
