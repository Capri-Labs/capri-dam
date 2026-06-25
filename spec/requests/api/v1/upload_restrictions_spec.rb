# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::UploadRestrictions', type: :request do
  # ── GET /api/v1/upload_restrictions ─────────────────────────────────────────
  path '/api/v1/upload_restrictions' do
    get 'Retrieve the current upload MIME-type restriction list' do
      tags        'Tools - Upload Restrictions'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Returns the configured list of allowed MIME types for asset uploads.
        An empty array means **all file types are permitted** (no restrictions active).
        Supports wildcards, e.g. `image/*` to allow all image formats.
      DESC

      response '200', 'restriction list returned' do
        schema type: :object,
               required: [ 'allowed_mime_types' ],
               properties: {
                 allowed_mime_types: {
                   type: :array,
                   items: { type: :string },
                   example: [ 'image/*', 'application/pdf' ],
                   description: 'Active allowlist. Empty = unrestricted.',
                 },
               }
        run_test!
      end
    end

    put 'Update the upload MIME-type restriction list (admin only)' do
      tags        'Tools - Upload Restrictions'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Persists a new MIME-type allowlist to the system settings store.
        Passing an empty array **disables all restrictions** so every file type is accepted.

        **Requires administrator privileges.**

        | Pattern | Effect |
        |---------|--------|
        | `image/*` | All image types (JPEG, PNG, WebP, …) |
        | `image/jpeg` | Only JPEG files |
        | `application/pdf` | Only PDF files |
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ :allowed_mime_types ],
        properties: {
          allowed_mime_types: {
            type: :array,
            items: { type: :string },
            example: [ 'image/*', 'application/pdf' ],
            description: 'New allowlist. Pass [] to remove all restrictions.',
          },
        },
      }

      response '200', 'restrictions saved' do
        schema type: :object,
               properties: {
                 allowed_mime_types: {
                   type: :array, items: { type: :string }
                 },
                 message: { type: :string, example: 'Upload restrictions saved successfully.' },
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
