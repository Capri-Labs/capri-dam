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
      security [ Bearer: [] ]
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
                   created_at:       { type: :string, format: 'date-time' },
                 },
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    post 'Create a new system connector' do
      tags 'System Connectors'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'system_connector' ],
        properties: {
          system_connector: {
            type: :object,
            required: [ 'name', 'provider_type' ],
            properties: {
              name:              { type: :string,  example: 'Cloudinary Production' },
              provider_type:     { type: :string,  example: 'cloudinary',
                                   description: 'cloudinary | brandfolder | bynder | ftp | http_api | aem' },
              endpoint:          { type: :string,  nullable: true,
                                   example: 'https://api.cloudinary.com/v1_1/mycloud' },
              auth_token:        { type: :string,  nullable: true,
                                   description: 'API key / Bearer token for the external system (credential_type: token)' },
              credential_type:   { type: :string, nullable: true, example: 'token',
                                   description: '"token" (static Bearer token, default) or "jwt_service_account" ' \
                                                '(Adobe IMS technical-account, private-key JWT exchange — used by AEM)' },
              integration_json:  { type: :string, nullable: true,
                                   description: 'Convenience field: the raw JSON blob copy-pasted from the Adobe ' \
                                                'Developer Console "Service Account (JWT)" credential page. When ' \
                                                'present, the server parses client_id/client_secret/private_key/' \
                                                'org/technical account id out of it and stores them (encrypted) as ' \
                                                'credentials_payload, forcing credential_type=jwt_service_account. ' \
                                                'The raw JSON itself is never persisted or echoed back.' },
              default_source_path: { type: :string, nullable: true,
                                     example: '/content/dam/US/marketing-assets/product-assets',
                                     description: 'Default DAM folder to scope migrations to (AEM only). Can be ' \
                                                  'overridden per-migration via start_migration\'s source_path param.' },
              concurrency_limit: { type: :integer, nullable: true, example: 5 },
              rps_limit:         { type: :integer, nullable: true, example: 10 },
              tdm_sanitation:    { type: :boolean, example: true,
                                   description: 'Whether to run TDM sanitation on imported metadata' },
            },
          },
        },
      }

      response '201', 'Connector created' do
        schema type: :object,
               properties: {
                 id:             { type: :integer },
                 name:           { type: :string },
                 provider_label: { type: :string },
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
      security [ Bearer: [] ]
      description 'Blank `auth_token` values are ignored so they do not overwrite the stored secret.'

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'system_connector' ],
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
              rps_limit:      { type: :integer,  nullable: true },
            },
          },
        },
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
      security [ Bearer: [] ]
      description <<~DESC
        Validates a set of credentials against the target provider **without
        saving them**. Use this in the connector setup wizard to verify the
        connection is working before committing the configuration.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'provider_type' ],
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
                              description: 'FTP remote directory path' },
        },
      }

      response '200', 'Connection successful' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string,  example: 'Successfully connected to Cloudinary.' },
               }
        run_test!
      end

      response '422', 'Connection failed' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 message: { type: :string,  example: 'Invalid API key.' },
               }
        run_test!
      end

      response '400', 'Missing required fields' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: false },
                 message: { type: :string },
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
      security [ Bearer: [] ]
      description <<~DESC
        Queues a `PreFlightAnalysisWorker` job that scans the source system to
        estimate asset count, total size, metadata quality score, and expected
        migration duration — without importing any assets.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'id' ],
        properties: {
          id: { type: :integer, description: 'SystemConnector ID to analyse' },
        },
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
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates a new `IngestionBatch` pre-populated with the connector's
        credentials and immediately fires `ExtractionWorker`. The connector
        must be in `status: active` to start a migration.

        For `credential_type: jwt_service_account` connectors, no static
        access token is snapshotted onto the batch — the extraction worker
        re-derives (and auto-refreshes) a live token on every chunk fetch,
        so long-running migrations survive token expiry.

        Monitor progress via `GET /api/v1/ingestion_batches/{batch_id}`.
      DESC

      parameter name: :payload, in: :body, required: false, schema: {
        type: :object,
        properties: {
          source_path: { type: :string, nullable: true,
                         example: '/content/dam/US/marketing-assets/product-assets',
                         description: 'DAM folder to scope this migration to. Falls back to the ' \
                                      'connector\'s default_source_path, then to the provider root.' },
        },
      }

      response '202', 'Migration started — batch summary returned' do
        schema type: :object,
               properties: {
                 message: { type: :string, example: 'Migration started.' },
                 batch:   { type: :object },
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

  # ===========================================================================
  # REFRESH TOKEN — POST /api/v1/system_connectors/{id}/refresh_token
  # ===========================================================================
  path '/api/v1/system_connectors/{id}/refresh_token' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'SystemConnector ID'

    post 'Force-refresh a jwt_service_account connector\'s IMS access token' do
      tags 'System Connectors'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Signs a fresh RS256 JWT from the connector's stored technical-account
        credentials and exchanges it with Adobe IMS for a new short-lived
        access token, persisting the result. Only valid for connectors with
        `credential_type: jwt_service_account`. Access tokens are also
        refreshed automatically in the background (see `AemTokenRefreshWorker`)
        whenever they are missing or near expiry.
      DESC

      response '200', 'Token refreshed' do
        schema type: :object,
               properties: {
                 token_status:              { type: :string, example: 'valid' },
                 access_token_expires_at:   { type: :string, format: 'date-time', nullable: true },
               }
        run_test!
      end

      response '422', 'Connector is not a jwt_service_account connector, or the IMS exchange failed' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Connector not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # REVOKE TOKEN — POST /api/v1/system_connectors/{id}/revoke_token
  # ===========================================================================
  path '/api/v1/system_connectors/{id}/revoke_token' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'SystemConnector ID'

    post 'Clear the locally cached IMS access token for a connector' do
      tags 'System Connectors'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Clears the cached access token so the next migration/refresh forces a
        fresh IMS exchange. This does **not** revoke the credential on Adobe's
        side — Adobe IMS has no public API for that. To fully invalidate a
        compromised technical account, rotate the client secret / regenerate
        the key pair in the Adobe Developer Console.
      DESC

      response '200', 'Token revoked (locally cleared)' do
        schema type: :object, properties: { token_status: { type: :string, example: 'revoked' } }
        run_test!
      end

      response '404', 'Connector not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
