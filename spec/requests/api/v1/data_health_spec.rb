# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::DataHealth', type: :request do
  # ===========================================================================
  # OVERVIEW — GET /api/v1/data_health/overview
  # ===========================================================================
  path '/api/v1/data_health/overview' do
    get 'Aggregate TDM & Storage Health overview metrics' do
      tags 'Data Health'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns a single JSON payload: storage composition (active, orphaned,
        dedup-prevented), duplicate group counts, connector summary, migration
        batch pipeline summary, duplicate-scan status, and a live debt-flag list.
      DESC

      response '200', 'Health overview returned' do
        schema type: :object,
               properties: {
                 storage:    { type: :object },
                 duplicates: { type: :object,
                               properties: {
                                 pending:   { type: :integer },
                                 resolved:  { type: :integer },
                                 dismissed: { type: :integer },
                                 total:     { type: :integer },
                               } },
                 connectors: { type: :object,
                               properties: {
                                 total: { type: :integer }, active: { type: :integer },
                                 idle:  { type: :integer }, disabled: { type: :integer }
                               } },
                 batches:    { type: :object,
                               properties: {
                                 total: { type: :integer }, active: { type: :integer },
                                 completed: { type: :integer }, failed: { type: :integer }
                               } },
                 scan:       { type: :object,
                               properties: {
                                 status:      { type: :string },
                                 last_scan_at: { type: :string, nullable: true },
                               } },
                 debt_flags:   { type: :array, items: { type: :object } },
                 generated_at: { type: :string, format: 'date-time' },
               }
        run_test!
      end

      response '403', 'Admin privileges required' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # CONNECTORS — GET /api/v1/data_health/connectors
  # ===========================================================================
  path '/api/v1/data_health/connectors' do
    get 'Per-connector health details including pre-flight analysis reports' do
      tags 'Data Health'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns every SystemConnector with its computed health_score (0–100),
        last_sync timestamp, assets_imported, batch count, and any available
        analysis_report from a previous pre-flight scan.
      DESC

      response '200', 'Connector health list returned' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id:              { type: :integer },
                   name:            { type: :string },
                   provider_type:   { type: :string },
                   provider_label:  { type: :string },
                   status:          { type: :string },
                   assets_imported: { type: :integer },
                   last_sync:       { type: :string, format: 'date-time', nullable: true },
                   tdm_sanitation:  { type: :boolean },
                   batches_count:   { type: :integer },
                   health_score:    { type: :integer, nullable: true },
                   analysis_report: { type: :object, nullable: true },
                 },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # REMEDIATE — POST /api/v1/data_health/remediate
  # ===========================================================================
  path '/api/v1/data_health/remediate' do
    post 'Queue a background remediation job for a specific debt type' do
      tags 'Data Health'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Enqueues a `DataHealthRemediationWorker` Sidekiq job.
        Valid types: `duplicates` | `missing_metadata` | `copyright` | `stale`.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'debt_type' ],
        properties: {
          debt_type: {
            type: :string,
            enum: %w[duplicates missing_metadata copyright stale],
            example: 'duplicates',
          },
        },
      }

      response '202', 'Remediation job accepted' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '422', 'Unknown debt type' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '403', 'Admin privileges required' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # Legacy: keep old /metrics path doc for backward-compat reference only
  # ===========================================================================
  path '/api/v1/data_health/metrics' do
    get '[Deprecated] Old TDM metrics endpoint — use /overview instead' do
      tags 'Data Health'
      produces 'application/json'
      security [ Bearer: [] ]
      deprecated true
      description 'Superseded by GET /api/v1/data_health/overview.'

      response '404', 'Endpoint removed' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
