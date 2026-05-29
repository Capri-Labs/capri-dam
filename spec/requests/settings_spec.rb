require 'swagger_helper'

RSpec.describe 'Settings', type: :request do
  # --- CLOUD STORAGE MANAGEMENT API ---

  path '/settings/update_storage' do
    patch 'Updates cloud storage provider configuration and sets active provider' do
      tags 'Infrastructure Settings - Storage'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          storage_config: {
            type: :object,
            properties: {
              # 🚨 CRITICAL: The required discriminator
              provider: { type: :string, enum: ['aws', 'cloudflare', 'digitalocean', 'google'], example: 'cloudflare' },

              # Provider-specific credentials
              region: { type: :string, example: 'auto' },
              access_key: { type: :string, example: 'KXA01BC2...' },
              # 🚨 Handle masked placeholder
              secret_key: { type: :string, example: '********', description: 'Will not overwrite if passed as masking placeholder' },
              bucket: { type: :string, example: 'dam-production-assets' },
              endpoint: { type: :string, nullable: true, example: 'https://<accountid>.r2.cloudflarestorage.com' }
            },
            required: ['provider']
          }
        },
        required: ['storage_config']
      }

      response '200', 'configuration saved successfully' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '422', 'unprocessable entity (failed to save)' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # --- INFRASTRUCTURE OBSERVABILITY API ---

  path '/settings/test_connection' do
    post 'Dynamically validates S3 connection credentials using AWS SDK' do
      tags 'Infrastructure Settings - Storage'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          storage_config: {
            type: :object,
            properties: {
              provider: { type: :string, example: 'aws' },
              region: { type: :string, example: 'us-east-1' },
              access_key: { type: :string },
              secret_key: { type: :string, description: 'Required. Handles masked placeholder by fetching existing secret.' },
              bucket: { type: :string },
              endpoint: { type: :string, nullable: true, description: 'Required for non-AWS compatible S3 backends' }
            },
            required: ['provider', 'region', 'access_key', 'secret_key', 'bucket']
          }
        },
        required: ['storage_config']
      }

      response '200', 'connection successful (Head Bucket)' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Connection successful! Found bucket dam-assets' }
               }
        run_test!
      end

      response '422', 'connection failed (AWS SDK Error)' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 error: { type: :string, description: 'The exact error message returned by the storage provider via SDK' }
               }
        run_test!
      end
    end
  end
end