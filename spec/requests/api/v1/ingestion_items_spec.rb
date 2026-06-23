# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::IngestionItems', type: :request do

  # ===========================================================================
  # SHOW — GET /api/v1/ingestion_items/{id}
  # ===========================================================================
  path '/api/v1/ingestion_items/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'IngestionItem database ID'

    get 'Retrieve a single ingestion item' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      description <<~DESC
        **Internal microservice endpoint.** Called by the TDM sanitation and AI
        enrichment workers to fetch the raw item data for processing.
      DESC

      response '200', 'Ingestion item returned' do
        schema type: :object,
               properties: {
                 id:                { type: :integer },
                 ingestion_batch_id: { type: :integer },
                 original_filename: { type: :string },
                 file_hash:         { type: :string },
                 file_size:         { type: :integer },
                 status:            { type: :string, example: 'pending' },
                 error_log:         { type: :string, nullable: true },
                 legacy_metadata:   { type: :object, nullable: true },
                 clean_properties:  { type: :object, nullable: true },
                 created_at:        { type: :string, format: 'date-time' }
               }
        run_test!
      end

      response '404', 'Item not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # UPDATE — PATCH /api/v1/ingestion_items/{id}
  # ===========================================================================
  path '/api/v1/ingestion_items/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'IngestionItem database ID'

    patch 'Update the status and clean properties of an ingestion item' do
      tags 'Ingestion & Migration'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        **Internal microservice endpoint.** Called by the AI enrichment worker
        to update `status` (e.g. from `ai_processing` to `review_needed`) and to
        write the sanitized `clean_properties` back to the database.

        When all items in a batch transition out of `pending`/`ai_processing`,
        the system automatically sets `batch.status = review_needed`.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: ['ingestion_item'],
        properties: {
          ingestion_item: {
            type: :object,
            properties: {
              status: {
                type: :string,
                example: 'review_needed',
                description: 'pending | ai_processing | review_needed | committed | failed'
              },
              error_log:         { type: :string, nullable: true },
              clean_properties:  {
                type: :object,
                description: 'Sanitized/enriched metadata ready for import into DAM'
              }
            }
          }
        }
      }

      response '200', 'Item updated successfully' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '422', 'Validation failed' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end

      response '404', 'Item not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

end

