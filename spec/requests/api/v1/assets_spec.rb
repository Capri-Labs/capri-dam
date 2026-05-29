require 'swagger_helper'

RSpec.describe 'Api::V1::Assets', type: :request do
  # --- SEARCH ENDPOINT ---
  path '/api/v1/search' do
    get 'Searches for assets' do
      tags 'Assets'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :q, in: :query, type: :string, required: false, description: 'Search term for title'
      parameter name: :format, in: :query, type: :string, required: false, description: 'Exact format match (e.g., JPEG)'

      response '200', 'search results returned' do
        schema type: :object,
               properties: {
                 total: { type: :integer },
                 results: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string },
                       title: { type: :string },
                       metadata: { type: :object },
                       url: { type: :string }
                     }
                   }
                 }
               }

        run_test!
      end
    end
  end

  # --- ASSET CREATION (MULTIPART UPLOAD) ---
  path '/api/v1/assets' do
    post 'Uploads a new asset' do
      tags 'Assets'
      consumes 'multipart/form-data'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :asset_payload, in: :formData, schema: {
        type: :object,
        properties: {
          file: { type: :string, format: :binary, description: 'The file to upload' },
          title: { type: :string, description: 'Optional override for the file name' },
          folder_id: { type: :integer, description: 'ID of the destination folder' }
        },
        required: ['file']
      }

      response '202', 'asset accepted for processing' do
        schema type: :object,
               properties: {
                 id: { type: :string },
                 status: { type: :string, example: 'processing' }
               }
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # --- ASSET MEMBER ENDPOINTS ---
  path '/api/v1/assets/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'Asset ID'

    delete 'Soft deletes an asset (moves to bin)' do
      tags 'Assets'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'asset moved to bin' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/assets/{id}/restore' do
    parameter name: :id, in: :path, type: :string, description: 'Asset ID'

    post 'Restores an asset from the bin' do
      tags 'Assets'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'asset restored' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/assets/{id}/permanent' do
    parameter name: :id, in: :path, type: :string, description: 'Asset ID'

    delete 'Permanently deletes an asset' do
      tags 'Assets'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'asset permanently deleted' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/assets/{id}/workflow_history' do
    parameter name: :id, in: :path, type: :string, description: 'Asset ID'

    get 'Retrieves workflow history for an asset' do
      tags 'Assets'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'workflow history returned' do
        schema type: :object,
               properties: {
                 active: { type: :boolean },
                 instance_status: { type: :string, nullable: true },
                 started_at: { type: :string, format: 'date-time', nullable: true },
                 tasks: { type: :array, items: { type: :object } }
               }
        run_test!
      end
    end
  end

  # --- THE RECYCLE BIN ---
  path '/api/v1/bin' do
    get 'Retrieves all soft-deleted assets and folders' do
      tags 'Assets'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'bin contents returned' do
        schema type: :object,
               properties: {
                 folders: { type: :array, items: { type: :object } },
                 assets: { type: :array, items: { type: :object } },
                 breadcrumbs: { type: :array, items: { type: :object } }
               }
        run_test!
      end
    end
  end
end