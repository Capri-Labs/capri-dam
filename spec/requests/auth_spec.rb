require 'swagger_helper'

RSpec.describe 'Authorization API', type: :request do
  path '/oauth/token' do
    post 'Requests an OAuth Access Token (Client Credentials Grant)' do
      tags 'Authorization (OAuth 2.0)'
      description <<-DESC
        This is the primary authentication endpoint for System Accounts and external integrations.#{" "}
        It converts your **Client ID** and **Client Secret** into a temporary **Bearer Access Token**.

        This token must be included in the header of all subsequent API requests as:
        `Authorization: Bearer <your_access_token>`
      DESC

      # Per OAuth 2.0 specification (RFC 6749), this endpoint consumes form-encoded data
      consumes 'application/x-www-form-urlencoded'
      produces 'application/json'

      # Rswag automatically converts these parameters into the correct request body format
      parameter name: :grant_type, in: :formData, type: :string,
                required: true, example: 'client_credentials',
                description: 'Must always be set to `client_credentials` for System Accounts.'

      parameter name: :client_id, in: :formData, type: :string,
                required: true, example: 'a-EoNWk8Jg_L7NbVvduggmw...',
                description: 'The Application ID generated via System Accounts settings.'

      parameter name: :client_secret, in: :formData, type: :string,
                required: true, example: 'NlMWSlbEFKxDetVLjO9v...',
                description: 'The Application Secret shown during account creation.'

      parameter name: :scope, in: :formData, type: :string,
                required: false, example: 'read write',
                description: 'Space-separated list of requested scopes. Must be subset of allowed scopes for the app.'

      response '200', 'access token issued successfully' do
        schema type: :object,
               properties: {
                 access_token: { type: :string, example: 'eyJhY2Nlc3NfdG9rZW4iOiJl...' },
                 token_type: { type: :string, example: 'Bearer' },
                 expires_in: { type: :integer, example: 7200, description: 'Time in seconds until expiration.' },
                 scope: { type: :string, example: 'read write' },
                 created_at: { type: :integer, example: 1716912345 },
               },
               required: [ 'access_token', 'token_type', 'expires_in' ]

        run_test!
      end

      response '401', 'unauthorized (invalid credentials)' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'invalid_client' },
                 error_description: { type: :string, example: 'Client authentication failed.' },
               }
        run_test!
      end
    end
  end
end
