require 'swagger_helper'

RSpec.describe 'Api::V1::Folders', type: :request do
  # Define the base path for these endpoints
  path '/api/v1/folders' do

    # 1. GET /api/v1/folders (Index)
    get 'Retrieves the folder tree' do
      tags 'Folders'
      produces 'application/json'

      # Optional: Document that this requires authentication
      # security [Bearer: []]

      response '200', 'folders retrieved successfully' do
        schema type: :object,
               properties: {
                 folders: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :integer, example: 42 },
                       name: { type: :string, example: '/Marketing/2026' }
                     },
                     required: [ 'id', 'name' ]
                   }
                 }
               }

        # The run_test! block executes the request during your test suite
        run_test!
      end
    end

    # 2. POST /api/v1/folders (Create)
    post 'Creates a new folder' do
      tags 'Folders'
      consumes 'application/json'
      produces 'application/json'

      # Define the expected JSON payload
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          folder: {
            type: :object,
            properties: {
              name: { type: :string, example: 'Q3 Campaigns' },
              parent_id: { type: :string, nullable: true, example: 'root' }
            },
            required: [ 'name' ]
          }
        },
        required: [ 'folder' ]
      }

      response '201', 'folder created' do
        # Provide the data that RSpec will use to execute the test
        let(:payload) { { folder: { name: 'Brand Assets', parent_id: 'root' } } }
        run_test!
      end

      response '422', 'unprocessable entity' do
        # Provide invalid data to test the failure state
        let(:payload) { { folder: { name: '' } } }
        run_test!
      end
    end
  end

  # Define the endpoints that take an ID parameter
  path '/api/v1/folders/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'Folder ID or "root"'

    # 3. GET /api/v1/folders/:id (Show)
    get 'Retrieves a folder and its contents' do
      tags 'Folders'
      produces 'application/json'

      response '200', 'folder contents found' do
        schema type: :object,
               properties: {
                 folders: { type: :array, items: { type: :object } },
                 assets: { type: :array, items: { type: :object } },
                 breadcrumbs: { type: :array, items: { type: :object } }
               }

        let(:id) { 'root' }
        run_test!
      end
    end
  end
end