# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::CollectionSettings', type: :request do
  # ===========================================================================
  # GET /api/v1/collection_settings
  # ===========================================================================
  path '/api/v1/collection_settings' do
    get 'Retrieve global collection / workspace settings' do
      tags 'Tools - Collection Settings'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns the global configuration defaults applied to all new collections
        and smart workspaces. Falls back to built-in defaults when no settings
        have been explicitly persisted.
      DESC

      response '200', 'Settings returned' do
        schema type: :object,
               required: %w[
                 default_similarity_threshold default_visibility
                 max_assets_per_collection auto_cdn_purge
                 smart_rule_schedule ttl_default_days enable_compliance_scan
               ],
               properties: {
                 default_similarity_threshold: {
                   type: :number, format: :float, example: 0.8,
                   description: 'Cosine similarity threshold used for new smart collections (0.5 – 0.99)'
                 },
                 default_visibility: {
                   type: :string, example: 'public', enum: %w[public private],
                   description: 'Default access level for newly created collections'
                 },
                 max_assets_per_collection: {
                   type: :integer, example: 500,
                   description: '0 = unlimited'
                 },
                 auto_cdn_purge: {
                   type: :boolean, example: true,
                   description: 'Invalidate CDN edge cache on every collection modification'
                 },
                 smart_rule_schedule: {
                   type: :string, example: 'daily',
                   enum: %w[hourly daily weekly manual],
                   description: 'How often the AI engine re-evaluates active smart rules'
                 },
                 ttl_default_days: {
                   type: :integer, example: 0,
                   description: '0 = no default TTL; positive values auto-archive after N days'
                 },
                 enable_compliance_scan: {
                   type: :boolean, example: false,
                   description: 'Run automated TDM usage-rights scan after each collection modification'
                 },
               }
        run_test!
      end
    end

    # -------------------------------------------------------------------------
    put 'Update global collection / workspace settings (admin only)' do
      tags 'Tools - Collection Settings'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Persists new global defaults for collection and workspace behaviour.
        Partial updates are supported — only the keys provided will be changed.

        **Requires administrator privileges.**
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'settings' ],
        properties: {
          settings: {
            type: :object,
            description: 'Subset of settings to update. Unknown keys are ignored.',
            properties: {
              default_similarity_threshold: { type: :number, format: :float, example: 0.75 },
              default_visibility:           { type: :string, example: 'private' },
              max_assets_per_collection:    { type: :integer, example: 250 },
              auto_cdn_purge:               { type: :boolean, example: false },
              smart_rule_schedule:          { type: :string, example: 'weekly' },
              ttl_default_days:             { type: :integer, example: 90 },
              enable_compliance_scan:       { type: :boolean, example: true },
            },
          },
        },
      }

      response '200', 'Settings saved' do
        schema type: :object,
               properties: {
                 message:  { type: :string, example: 'Collection settings saved successfully.' },
                 settings: { type: :object },
               }
        run_test!
      end

      response '403', 'Forbidden — administrator privileges required' do
        schema type: :object,
               properties: { error: { type: :string, example: 'Administrator privileges required.' } }
        run_test!
      end

      response '422', 'Unprocessable entity' do
        schema type: :object,
               properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
