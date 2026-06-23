# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::CdnConfigurations', type: :request do

  # ===========================================================================
  # INDEX — GET /api/v1/cdn_configurations
  # ===========================================================================
  path '/api/v1/cdn_configurations' do

    get 'Retrieve CDN configuration for all supported providers' do
      tags 'CDN & Settings'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Returns the active CDN configuration for Fastly, Cloudflare, and Akamai.
        **Secrets are masked** in the response — only the last 4 characters of
        each secret value are visible (e.g. `••••••••k9Xz`). To update a
        provider, use `PUT /api/v1/cdn_configurations`.
      DESC

      response '200', 'CDN configurations returned (secrets masked)' do
        schema type: :object,
               properties: {
                 fastly: {
                   type: :object,
                   properties: {
                     is_active: { type: :boolean },
                     settings:  { type: :object,
                                   description: 'Provider-specific settings with secrets masked' }
                   }
                 },
                 cloudflare: {
                   type: :object,
                   properties: {
                     is_active: { type: :boolean },
                     settings:  { type: :object }
                   }
                 },
                 akamai: {
                   type: :object,
                   properties: {
                     is_active: { type: :boolean },
                     settings:  { type: :object }
                   }
                 }
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    put 'Update CDN configuration for a provider' do
      tags 'CDN & Settings'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Creates or updates the `CdnConfiguration` for the specified `provider`.
        Values containing `••••` (the masking sentinel) are automatically
        excluded from the update to prevent overwriting stored secrets with
        masked placeholder values returned by the GET endpoint.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: ['provider'],
        properties: {
          provider:  { type: :string, example: 'fastly',
                       description: 'fastly | cloudflare | akamai' },
          is_active: { type: :boolean, example: true },
          settings: {
            type: :object,
            description: 'Provider-specific key-value settings (e.g. service_id, api_key)',
            example: { service_id: 'svc_abc123', api_key: 'sk_live_xyz' }
          }
        }
      }

      response '200', 'CDN configuration updated' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string, example: 'Fastly configuration updated.' }
               }
        run_test!
      end

      response '422', 'Validation failed' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

end

