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
                 created_at:        { type: :string, format: 'date-time' },
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
        required: [ 'ingestion_item' ],
        properties: {
          ingestion_item: {
            type: :object,
            properties: {
              status: {
                type: :string,
                example: 'review_needed',
                description: 'pending | ai_processing | review_needed | committed | failed',
              },
              error_log:         { type: :string, nullable: true },
              clean_properties:  {
                type: :object,
                description: 'Sanitized/enriched metadata ready for import into DAM',
              },
            },
          },
        },
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

  describe "coverage scenarios" do
    let(:admin) { create(:user, :admin) }

    before { sign_in admin }

    it "lists ingestion items without applying a batch filter when no batch_id is provided" do
      first = create(:ingestion_item)
      second = create(:ingestion_item)

      get "/api/v1/ingestion_items", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("items").map { |item| item.fetch("id") }).to include(first.id, second.id)
    end

    it "returns validation errors for invalid updates" do
      item = create(:ingestion_item)
      allow(IngestionItem).to receive(:find).with(item.id.to_s).and_return(item)
      allow(item).to receive(:update).and_return(false)
      allow(item).to receive_message_chain(:errors, :full_messages).and_return([ "Status is invalid" ])

      patch "/api/v1/ingestion_items/#{item.id}",
            params: { ingestion_item: { status: "committed" } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch("errors")).to include("Status is invalid")
    end

    it "keeps transforming batches unchanged while other active items remain" do
      batch = create(:ingestion_batch, status: :transforming)
      item = create(:ingestion_item, ingestion_batch: batch, status: :ai_processing)
      create(:ingestion_item, ingestion_batch: batch, status: :pending)

      patch "/api/v1/ingestion_items/#{item.id}",
            params: { ingestion_item: { status: :committed } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(batch.reload.status).to eq("transforming")
    end
  end
end
