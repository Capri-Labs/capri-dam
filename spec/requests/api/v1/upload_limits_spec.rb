# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::UploadLimits', type: :request do
  # ── GET /api/v1/upload_limits ───────────────────────────────────────────────
  path '/api/v1/upload_limits' do
    get 'Retrieve the current maximum upload file size' do
      tags        'Tools - Upload Limits'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Returns the configured maximum upload file size, in bytes, enforced by
        {Api::V1::AssetsController#create}. Defaults to 2 GB (2147483648 bytes)
        when no admin override has been saved, matching AEM's documented
        default asset upload size limit.
      DESC

      response '200', 'upload limit returned' do
        schema type: :object,
               required: [ 'max_upload_size_bytes' ],
               properties: {
                 max_upload_size_bytes: {
                   type: :integer,
                   example: 2_147_483_648,
                   description: 'Maximum allowed upload size in bytes.',
                 },
               }
        run_test!
      end
    end

    put 'Update the maximum upload file size (admin only)' do
      tags        'Tools - Upload Limits'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Persists a new maximum upload size (in bytes) to the system settings
        store. Enforced both server-side (`413 Payload Too Large` on oversized
        uploads) and reflected in the upload UI.

        **Requires administrator privileges.**
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ :max_upload_size_bytes ],
        properties: {
          max_upload_size_bytes: {
            type: :integer,
            example: 2_147_483_648,
            description: 'New maximum upload size, in bytes. Must be a positive integer.',
          },
        },
      }

      response '200', 'limit saved' do
        schema type: :object,
               properties: {
                 max_upload_size_bytes: { type: :integer },
                 message: { type: :string, example: 'Upload size limit saved successfully.' },
               }
        run_test!
      end

      response '403', 'forbidden – admin privileges required' do
        schema type: :object,
               properties: { error: { type: :string, example: 'Administrator privileges required.' } }
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema type: :object,
               properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
