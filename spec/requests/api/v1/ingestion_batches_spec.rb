# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::IngestionBatches', type: :request do
  # ===========================================================================
  # INDEX — GET /api/v1/ingestion_batches
  # ===========================================================================
  path '/api/v1/ingestion_batches' do
    get 'List the 50 most recent migration batches' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns summary records for the 50 most recent ingestion batches ordered
        by `created_at DESC`. Use this to build the batch monitoring dashboard.
      DESC

      response '200', 'Batch list returned' do
        schema type: :object,
               properties: {
                 batches: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:             { type: :string, format: 'uuid' },
                       name:           { type: :string, example: 'Cloudinary Migration — 2026-06-20 14:30' },
                       source_type:    { type: :string, example: 'cloudinary' },
                       status:         { type: :string, example: 'review_needed',
                                         description: 'initializing | extracting | transforming | review_needed | committed | failed' },
                       started_at:     { type: :string, format: 'date-time' },
                       completed_at:   { type: :string, format: 'date-time', nullable: true },
                     },
                   },
                 },
                 meta: {
                   type: :object,
                   properties: {
                     total:    { type: :integer },
                     page:     { type: :integer },
                     per_page: { type: :integer },
                   },
                 },
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    post 'Initialize a new migration batch' do
      tags 'Ingestion & Migration'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates a new `IngestionBatch` record and immediately fires the
        `ExtractionWorker` Sidekiq job. The batch progresses through these states:

        `initializing` → `extracting` → `transforming` → `review_needed`

        Once in `review_needed`, a human operator reviews the batch in the
        BatchReviewWorkspace and calls `POST /commit` to approve it.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'ingestion_batch' ],
        properties: {
          ingestion_batch: {
            type: :object,
            required: [ 'name', 'source_type' ],
            properties: {
              name:         { type: :string,  example: 'Cloudinary Legacy Import' },
              source_type:  { type: :string,  example: 'cloudinary',
                              description: 'cloudinary | brandfolder | bynder | ftp | http_api' },
              connector_id: { type: :integer, nullable: true,
                              description: 'ID of the SystemConnector to use for credentials' },
              notes:        { type: :string,  nullable: true },
              source_credentials: {
                type: :object,
                description: 'Provider-specific credentials map (stored encrypted). Prefer using connector_id.',
                example: { endpoint: 'https://api.cloudinary.com/v1_1/mycloud', auth_token: 'sk_test_abc' },
              },
            },
          },
        },
      }

      response '201', 'Batch created and extraction pipeline started' do
        schema type: :object,
               properties: {
                 message: { type: :string },
                 batch:   { type: :object },
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

  # ===========================================================================
  # STATS — GET /api/v1/ingestion_batches/stats
  # ===========================================================================
  path '/api/v1/ingestion_batches/stats' do
    get 'Aggregate migration statistics across all batches' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns roll-up metrics used by the ingestion dashboard: total/active/
        completed/failed batch counts, asset counts, duplicate blocks, and
        estimated storage/cost savings. Safe to poll frequently (read-only).
      DESC

      response '200', 'Aggregate stats returned' do
        schema type: :object,
               properties: {
                 total_batches:              { type: :integer },
                 active_batches:             { type: :integer },
                 completed_batches:          { type: :integer },
                 failed_batches:             { type: :integer },
                 total_assets_staged:        { type: :integer },
                 total_assets_committed:     { type: :integer },
                 total_duplicates_blocked:   { type: :integer },
                 total_errors:               { type: :integer },
                 estimated_storage_saved_gb: { type: :number, format: :float },
                 estimated_cost_savings_usd: { type: :number, format: :float },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # DESTROY — DELETE /api/v1/ingestion_batches/{id}
  # ===========================================================================
  path '/api/v1/ingestion_batches/{id}' do
    parameter name: :id, in: :path, type: :string, required: true,
              description: 'IngestionBatch UUID'

    delete 'Delete a failed migration batch' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Permanently removes a batch and all its ingestion items. Only batches in `failed` state can be deleted.'

      response '200', 'Batch deleted' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '422', 'Batch is not in failed state' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Batch not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end


  path '/api/v1/ingestion_batches/{id}' do
    parameter name: :id, in: :path, type: :string, required: true,
              description: 'IngestionBatch UUID'

    get 'Retrieve a batch with its paginated ingestion items' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :status, in: :query, type: :string, required: false,
                description: 'Filter items by status (pending | ai_processing | review_needed | committed | failed)'
      parameter name: :page,   in: :query, type: :integer, required: false,
                description: 'Page number (default: 1, 50 items per page)'

      response '200', 'Batch details and items returned' do
        schema type: :object,
               properties: {
                 batch: { type: :object },
                 items: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:                { type: :integer },
                       original_filename: { type: :string },
                       file_hash:         { type: :string, description: 'SHA-256 hash' },
                       file_size:         { type: :integer },
                       status:            { type: :string },
                       error_log:         { type: :string, nullable: true },
                       legacy_metadata:   { type: :object, nullable: true },
                       clean_properties:  { type: :object, nullable: true },
                       created_at:        { type: :string, format: 'date-time' },
                     },
                   },
                 },
                 meta: {
                   type: :object,
                   properties: {
                     total:    { type: :integer },
                     page:     { type: :integer },
                     per_page: { type: :integer, example: 50 },
                   },
                 },
               }
        run_test!
      end

      response '404', 'Batch not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # COMMIT — POST /api/v1/ingestion_batches/{id}/commit
  # ===========================================================================
  path '/api/v1/ingestion_batches/{id}/commit' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'IngestionBatch ID'

    post 'Human-approve and commit a batch to the DAM' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Transitions the batch from `review_needed` to `committed` and fires the
        `MigrationCommitWorker` to physically import all approved assets.
        Can only be called when `status == review_needed`. You will receive
        an email notification when the import is complete.
      DESC

      response '200', 'Commit pipeline started' do
        schema type: :object,
               properties: {
                 message: { type: :string },
                 batch:   { type: :object },
               }
        run_test!
      end

      response '422', 'Batch is not in review_needed state' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Batch not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # ABORT — POST /api/v1/ingestion_batches/{id}/abort
  # ===========================================================================
  path '/api/v1/ingestion_batches/{id}/abort' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'IngestionBatch ID'

    post 'Abort a migration batch without committing' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Sets the batch status to `failed`. Cannot be called on already-committed batches.'

      response '200', 'Batch aborted' do
        schema type: :object,
               properties: {
                 message: { type: :string },
                 batch:   { type: :object },
               }
        run_test!
      end

      response '422', 'Cannot abort a committed batch' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Batch not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # REPORT — GET /api/v1/ingestion_batches/{id}/report
  # ===========================================================================
  path '/api/v1/ingestion_batches/{id}/report' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'IngestionBatch ID'

    get 'Retrieve or generate the migration statistics report for a batch' do
      tags 'Ingestion & Migration'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns pre-computed migration stats (success count, failure count, TDM
        quality scores, duplicate rates). If the report has not been generated yet
        on a committed batch, a `202 Accepted` is returned and report generation
        is queued in the background via `MigrationReportWorker`.
      DESC

      response '200', 'Report returned' do
        schema type: :object,
               properties: {
                 batch:  { type: :object },
                 report: { type: :object, description: 'Migration statistics snapshot' },
               }
        run_test!
      end

      response '202', 'Report is being generated — check back shortly' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '404', 'Batch not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
