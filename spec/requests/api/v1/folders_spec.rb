# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Folders', type: :request do

  # ===========================================================================
  # INDEX — GET /api/v1/folders
  # ===========================================================================
  path '/api/v1/folders' do

    get 'Retrieve the full folder tree (flat list with paths)' do
      tags 'Folders'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Returns every active folder as a flat sorted list with fully-qualified
        path names (e.g. `/Marketing/2026/Campaigns`). Used to populate folder-
        picker dropdowns across the UI. Built in O(n) using a single query + in-
        memory tree traversal — safe for large folder structures.
      DESC

      response '200', 'Folders retrieved successfully' do
        schema type: :object,
               properties: {
                 folders: {
                   type: :array,
                   items: {
                     type: :object,
                     required: ['id', 'name'],
                     properties: {
                       id:   { type: :integer, example: 42 },
                       name: { type: :string,  example: '/Marketing/2026' }
                     }
                   }
                 }
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    post 'Create a new folder' do
      tags 'Folders'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: ['folder'],
        properties: {
          folder: {
            type: :object,
            required: ['name'],
            properties: {
              name:      { type: :string, example: 'Q3 Campaigns' },
              parent_id: { type: :string, nullable: true, example: 'root',
                           description: 'Parent folder ID or "root" to create at top level' }
            }
          }
        }
      }

      response '201', 'Folder created successfully' do
        let(:payload) { { folder: { name: 'Brand Assets', parent_id: 'root' } } }
        run_test!
      end

      response '422', 'Validation failed (e.g., blank name)' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        let(:payload) { { folder: { name: '' } } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW — GET /api/v1/folders/{id}
  # ===========================================================================
  path '/api/v1/folders/{id}' do
    parameter name: :id, in: :path, type: :string, required: true,
              description: 'Folder ID or the string `"root"` to browse the top level'

    get 'Retrieve a folder and its direct child contents' do
      tags 'Folders'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Returns immediate sub-folders, assets in this folder, and the breadcrumb
        trail back to root. Pass `id=root` to list all top-level items.
        Only active (non-trashed) items are returned.
      DESC

      response '200', 'Folder contents returned' do
        schema type: :object,
               properties: {
                 folders: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:   { type: :integer },
                       name: { type: :string }
                     }
                   }
                 },
                 assets: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:         { type: :integer },
                       uuid:       { type: :string, format: :uuid },
                       title:      { type: :string },
                       status:     { type: :string, example: 'ready' },
                       version:    { type: :integer },
                       properties: { type: :object },
                       url:        { type: :string, nullable: true }
                     }
                   }
                 },
                 breadcrumbs: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:   { type: :string },
                       name: { type: :string }
                     }
                   }
                 }
               }
        let(:id) { 'root' }
        run_test!
      end

      response '404', 'Folder not found or has been deleted' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # RESTORE — POST /api/v1/folders/{id}/restore
  # ===========================================================================
  path '/api/v1/folders/{id}/restore' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Folder ID'

    post 'Restore a soft-deleted folder from the Recycle Bin' do
      tags 'Folders'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'Folder restored to active state' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Folder restored' }
               }
        run_test!
      end

      response '404', 'Folder not found in the bin' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # PERMANENT DELETE — DELETE /api/v1/folders/{id}/permanent
  # ===========================================================================
  path '/api/v1/folders/{id}/permanent' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Folder ID'

    delete 'Permanently delete a folder from the Recycle Bin' do
      tags 'Folders'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        **Irreversible.** Destroys the folder database record. Also dispatches a
        CDN invalidation job to drop any cached assets under this folder from
        edge nodes. Assets inside the folder should be permanently deleted
        separately (or handled by `dependent: :destroy` on the model association).
      DESC

      response '200', 'Folder permanently deleted' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Folder permanently deleted' }
               }
        run_test!
      end

      response '404', 'Folder not found in the bin' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

end