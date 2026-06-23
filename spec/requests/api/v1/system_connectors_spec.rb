# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::SystemConnectors', type: :request do

  # ===========================================================================
  # INDEX — GET /api/v1/system_connectors
  # ===========================================================================
  path '/api/v1/system_connectors' do

    get 'List all system connectors (ingestion bridges)' do
      tags 'System Connectors'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Returns all configured system connectors ordered by `created_at DESC`.
        A connector is a named integration bridge to an external DAM/storage
        provider (Cloudinary, Brandfolder, Bynder, FTP, HTTP API, etc.).
      DESC

      response '200', 'Connectors returned' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id:               { type: :integer },
                   name:             { type: :string, example: 'Cloudinary Production' },
                   provider_type:    { type: :string, example: 'cloudinary' },
                   provider_label:   { type: :string, example: 'Cloudinary' },
                   endpoint:         { type: :string, nullable: true },
                   status:           { type: :string, example: 'active',
                                       description: 'idle | active | error' },
                   assets_imported:  { type: :integer, example: 0 },
                   concurrency_limit: { type: :integer, nullable: true },
                   rps_limit:        { type: :integer, nullable: true },
                   created_at:       { type: :string, format: 'date-time' }
                 }
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    post 'Create a new system connector' do
      tags 'System Connectors'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: ['system_connector'],
        properties: {
          system_connector: {
            type: :object,
            required: ['name', 'provider_type'],
            properties: {
              name:              { type: :string,  example: 'Cloudinary Production' },
              provider_type:     { type: :string,  example: 'cloudinary',
                                   description: 'cloudinary | brandfolder | bynder | ftp | http_api' },
              endpoint:          { type: :string,  nullable: true,
                                   example: 'https://api.cloudinary.com/v1_1/mycloud' },
              auth_token:        { type: :string,  nullable: true,
                                   description: 'API key / Bearer token for the external system' },
              concurrency_limit: { type: :integer, nullable: true, example: 5 },
              rps_limit:         { type: :integer, nullable: true, example: 10 },
              tdm_sanitation:    { type: :boolean, example: true,
                                   description: 'Whether to run TDM sanitation on imported metadata' }
            }
          }
        }
      }

      response '201', 'Connector created' do
        schema type: :object,
               properties: {
                 id:             { type: :integer },
                 name:           { type: :string },
                 provider_label: { type: :string }
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
  # UPDATE — PATCH/PUT /api/v1/system_connectors/{id}
  # ===========================================================================
  path '/api/v1/system_connectors/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'System connector ID'

    patch 'Update a system connector' do
      tags 'System Connectors'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]
      description 'Blank `auth_token` values are ignored so they do not overwrite the stored secret.'

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: ['system_connector'],
        properties: {
          system_connector: {
            type: :object,
            properties: {
              name:           { type: :string },
              endpoint:       { type: :string,  nullable: true },
              auth_token:     { type: :string,  nullable: true,
                                description: 'Leave blank to keep the existing secret' },
              status:         { type: :string,  example: 'active' },
              concurrency_limit: { type: :integer, nullable: true },
              rps_limit:      { type: :integer,  nullable: true }
            }
          }
        }
      }

      response '200', 'Connector updated' do
        run_test!
      end

      response '404', 'Connector not found' do
        schema type: :object, properties: { error: { type: :string } }
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
  # TEST CONNECTION — POST /api/v1/system_connectors/test_connection
  # ===========================================================================
  path '/api/v1/system_connectors/test_connection' do
    post 'Test connector credentials before saving' do
      tags 'System Connectors'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Validates a set of credentials against the target provider **without
        saving them**. Use this in the connector setup wizard to verify the
        connection is working before committing the configuration.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: ['provider_type'],
        properties: {
          provider_type:    { type: :string, example: 'cloudinary' },
          endpoint:         { type: :string, nullable: true },
          auth_token:       { type: :string, nullable: true },
          cloud_name:       { type: :string, nullable: true,
                              description: 'Required for Cloudinary' },
          brandfolder_key:  { type: :string, nullable: true },
          username:         { type: :string, nullable: true,
                              description: 'FTP username' },
          password:         { type: :string, nullable: true,
                              description: 'FTP password' },
          remote_path:      { type: :string, nullable: true,
                              description: 'FTP remote directory path' }
        }
      }

      response '200', 'Connection successful' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string,  example: 'Successfully connected to Cloudinary.' }
               }
        run_test!
      end

      response '422', 'Connection failed' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 message: { type: :string,  example: 'Invalid API key.' }
               }
        run_test!
      end

      response '400', 'Missing required fields' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 message: { type: :string }
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # PRE-FLIGHT ANALYSIS — POST /api/v1/system_connectors/pre_flight_analysis
  # ===========================================================================
  path '/api/v1/system_connectors/pre_flight_analysis' do
    post 'Kick off a pre-flight analysis on a connector (async)' do
      tags 'System Connectors'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Queues a `PreFlightAnalysisWorker` job that scans the source system to
        estimate asset count, total size, metadata quality score, and expected
        migration duration — without importing any assets.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: ['id'],
        properties: {
          id: { type: :integer, description: 'SystemConnector ID to analyse' }
        }
      }

      response '202', 'Pre-flight analysis started' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # START MIGRATION — POST /api/v1/system_connectors/{id}/start_migration
  # ===========================================================================
  path '/api/v1/system_connectors/{id}/start_migration' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'SystemConnector ID'

    post 'Start a full migration from a connector source' do
      tags 'System Connectors'
      produces 'application/json'
      security [Bearer: []]
      description <<~DESC
        Creates a new `IngestionBatch` pre-populated with the connector's
        credentials and immediately fires `ExtractionWorker`. The connector
        must be in `status: active` to start a migration.

        Monitor progress via `GET /api/v1/ingestion_batches/{batch_id}`.
      DESC

      response '202', 'Migration started — batch summary returned' do
        schema type: :object,
               properties: {
                 message: { type: :string, example: 'Migration started.' },
                 batch:   { type: :object }
               }
        run_test!
      end

      response '422', 'Connector is not in active status' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Connector not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

end

