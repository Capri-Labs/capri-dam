require 'swagger_helper'

RSpec.describe 'api/v1/assets', type: :request do
  path '/api/v1/search' do
    get('search assets') do
      tags 'Search'
      produces 'application/json'
      security [ bearer_auth: [] ]

      parameter name: :q, in: :query, type: :string, description: 'Search query'
      parameter name: :format, in: :query, type: :string, description: 'Filter by image format'

      response(200, 'successful') do
        schema type: :object,
               properties: {
                 total: { type: :integer },
                 results: { type: :array, items: { type: :object } }
               }
        run_test!
      end

      response(401, 'unauthorized') do
        run_test!
      end
    end
  end

  path '/api/v1/assets' do
    post('upload asset') do
      tags 'Upload'
      consumes 'multipart/form-data'
      security [ bearer_auth: [] ]

      parameter name: :file, in: :formData, type: :file, required: true
      parameter name: :title, in: :formData, type: :string

      response(202, 'accepted') do
        run_test!
      end
    end
  end
end