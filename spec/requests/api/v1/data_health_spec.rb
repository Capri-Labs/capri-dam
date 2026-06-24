# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::DataHealth', type: :request do

  # ── GET /admin/migrations/health (data health metrics) ───────────────────────
  path '/api/v1/data_health/metrics' do
    get 'Retrieve TDM storage health and technical-debt metrics' do
      tags        'Data & Migrations - Health'
      produces    'application/json'
      security    [Bearer: []]
      description <<~DESC
        Returns storage utilisation figures and a prioritised list of technical-debt
        flags (orphaned assets, missing usage rights, stale media) that require
        remediation action.

        **Note:** In high-volume environments these metrics are cached in Redis and
        refreshed nightly to prevent excessive DB load.
      DESC

      response '200', 'health metrics returned' do
        schema type: :object,
               properties: {
                 storage: {
                   type: :object,
                   properties: {
                     total_allocated_tb:       { type: :number, example: 20.0 },
                     active_used_tb:           { type: :number, example: 4.32 },
                     orphaned_wasted_tb:       { type: :number, example: 0.12 },
                     duplicates_prevented_tb:  { type: :number, example: 0.85 }
                   }
                 },
                 debt_flags: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:     { type: :string, example: 'd1' },
                       type:   { type: :string, example: 'orphaned' },
                       title:  { type: :string, example: 'Orphaned Legacy Assets' },
                       count:  { type: :integer, example: 142 },
                       impact: { type: :string, enum: %w[Critical High Medium Low], example: 'High' }
                     }
                   }
                 }
               }
        run_test!
      end
    end
  end

end

