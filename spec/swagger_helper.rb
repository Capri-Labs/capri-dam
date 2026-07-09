# frozen_string_literal: true

require 'rails_helper'

RSpec.configure do |config|
  config.openapi_root = Rails.root.join('swagger').to_s

  # openapi_specs= is the current API (swagger_docs= was deprecated in rswag-specs 2.x)
  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Capri DAM API',
        version: 'v1',
        description: <<~DESC,
          An enterprise-grade, cloud-agnostic Digital Asset Management system designed for zero noise operations and high-scale automation.

          ### Core Capabilities
          * **Asset Lifecycle Management**: Upload, process, and retrieve media assets asynchronously.
          * **Workflow Automation**: Configurable event-driven state machines for asset approval and metadata pipelines.
          * **Operational Governance**: Granular role-based access control (RBAC), hierarchical user groups, and comprehensive administrative oversight.
          * **Cloud-Agnostic Storage**: Plug-and-play architecture supporting AWS S3, Cloudflare R2, Google Cloud Storage, and local environments.

          ### Authentication
          This API utilizes OAuth 2.0 for secure access. System-to-system integrations should utilize the Client Credentials grant type.

          1. Call `POST /oauth/token` with your `client_id` and `client_secret`.
          2. Click the **Authorize** button on this page and enter the resulting token.
        DESC
        termsOfService: 'https://github.com/Capri-Labs/capri-dam',
        contact: {
          name: 'Ashok Pelluru | Operational Governance & Architecture',
          url: 'https://github.com/Capri-Labs/capri-dam',
        },
        license: {
          name: 'MIT License',
          url: 'https://opensource.org/licenses/MIT',
        },
      },
      paths: {},
      servers: [
        {
          url: 'http://localhost:3000',
          description: 'Local Development Server',
        },
        {
          url: 'https://api.yourdam.com',
          description: 'Production Environment',
        },
      ],
      components: {
        securitySchemes: {
          Bearer: {
            type: :http,
            scheme: :bearer,
            description: 'Enter your OAuth 2.0 Bearer token to authenticate requests.',
          },
        },
        schemas: {
          FolderPolicy: {
            type: :object,
            properties: {
              id:               { type: :integer },
              group_id:         { type: :integer },
              group_name:       { type: :string, nullable: true },
              read_access:      { type: :boolean },
              modify_access:    { type: :boolean },
              create_access:    { type: :boolean },
              delete_access:    { type: :boolean },
              replicate_access: { type: :boolean },
              manage_access:    { type: :boolean },
              explicit_deny:    { type: :boolean },
            },
          },
          CustomNodeDefinition: {
            type: :object,
            properties: {
              id:                 { type: :integer },
              key:                { type: :string, example: "acme_watermark" },
              node_type:          { type: :string, example: "plugin:acme_watermark" },
              name:               { type: :string },
              description:        { type: :string, nullable: true },
              icon:               { type: :string, nullable: true },
              category:           { type: :string, example: "custom" },
              color:              { type: :string, example: "#6366f1" },
              config_schema:      { type: :array, items: { type: :object } },
              runtime:            { type: :object, description: "Secrets are never serialized." },
              status:             { type: :string, enum: %w[draft enabled disabled] },
              failure_count:      { type: :integer },
              last_error:         { type: :string, nullable: true },
              last_dispatched_at: { type: :string, format: "date-time", nullable: true },
              circuit_open:       { type: :boolean },
              created_by:         { type: :string, nullable: true },
              created_at:         { type: :string, format: "date-time" },
              updated_at:         { type: :string, format: "date-time" },
            },
          },
          AgentWorkflow: {
            type: :object,
            properties: {
              id:              { type: :integer },
              name:            { type: :string },
              description:     { type: :string, nullable: true },
              trigger_event:  { type: :string, example: 'asset.staged' },
              agent_model:    { type: :string, example: 'gpt-4o-mini' },
              tools_enabled:  { type: :array, items: { type: :string } },
              active:         { type: :boolean },
              metadata:       { type: :object },
              created_by:     { type: :string, nullable: true },
              created_at:     { type: :string, format: 'date-time' },
              updated_at:     { type: :string, format: 'date-time' },
              reliability:    { type: :number, nullable: true, example: 99.2 },
              avg_duration_ms: { type: :integer, nullable: true, example: 1400 },
              execution_count: { type: :integer },
            },
          },
          AiBatchJob: {
            type: :object,
            properties: {
              id:               { type: :integer },
              task_type:        { type: :string, example: 'metadata_extraction' },
              task_label:       { type: :string, nullable: true, example: 'Metadata Extraction' },
              target_scope:     { type: :string, example: 'missing_metadata' },
              status:           { type: :string, example: 'running', enum: %w[queued running paused completed failed cancelled] },
              concurrency:      { type: :integer, example: 25 },
              options:          { type: :object },
              total_count:      { type: :integer },
              processed_count:  { type: :integer },
              succeeded_count:  { type: :integer },
              failed_count:     { type: :integer },
              progress_percent: { type: :integer, example: 42 },
              error_message:    { type: :string, nullable: true },
              created_by:       { type: :string, nullable: true },
              started_at:       { type: :string, format: 'date-time', nullable: true },
              completed_at:     { type: :string, format: 'date-time', nullable: true },
              created_at:       { type: :string, format: 'date-time' },
              updated_at:       { type: :string, format: 'date-time' },
            },
          },
          C2paConfiguration: {
            type: :object,
            properties: {
              id:                      { type: :integer },
              gateway_c2pa_enabled:    { type: :boolean },
              auto_verify_on_ingest:   { type: :boolean },
              auto_sign_on_ingest:     { type: :boolean },
              require_c2pa_on_import:  { type: :boolean },
              ai_disclosure_required:  { type: :boolean },
              signing_issuer_name:     { type: :string, nullable: true },
              signing_org:             { type: :string, nullable: true },
              trust_store_urls:        { type: :array, items: { type: :string } },
              verification_strictness: { type: :string, enum: %w[lenient strict] },
              policy_notes:            { type: :string, nullable: true },
              updated_at:              { type: :string, format: 'date-time' },
            },
          },
          AssetProvenanceRecord: {
            type: :object,
            properties: {
              id:                      { type: :integer },
              asset_id:                { type: :string, format: 'uuid' },
              asset_uuid:              { type: :string, nullable: true },
              asset_title:             { type: :string, nullable: true },
              manifest_status:         { type: :string, enum: %w[unchecked verified ai_generated ai_modified missing invalid signed error] },
              manifest_data:           { type: :object },
              claim_generator:         { type: :string, nullable: true },
              is_ai_modified:          { type: :boolean },
              ai_tools_used:           { type: :array, items: { type: :string } },
              verified_at:             { type: :string, format: 'date-time', nullable: true },
              signed_at:               { type: :string, format: 'date-time', nullable: true },
              signer_name:             { type: :string, nullable: true },
              signer_cert_fingerprint: { type: :string, nullable: true },
              error_detail:            { type: :string, nullable: true },
              created_at:              { type: :string, format: 'date-time' },
              updated_at:              { type: :string, format: 'date-time' },
            },
          },
        },
      },
    },
  }

  config.openapi_format = :yaml

  # rswag_dry_run controls whether run_test! actually makes HTTP requests:
  #   true  — run_test! is a no-op; YAML is generated from DSL metadata only.
  #            Safe for `make swagger-docs` (doc generation).
  #   false — run_test! fires real HTTP requests and validates response codes.
  #            Used by `make test-api-docs` (API validation).
  #
  # Control via env: RSWAG_DRY_RUN=0 → execute;  anything else (or absent) → dry-run.
  config.rswag_dry_run = ENV.fetch('RSWAG_DRY_RUN', '1') != '0'
end
