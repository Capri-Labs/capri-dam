# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Preservation API', type: :request do
  let(:admin_user) { create(:user, admin: true) }
  let(:asset)      { create(:asset) }

  # ── GET /api/v1/preservation/fixity ──────────────────────────────────────────
  path '/api/v1/preservation/fixity' do
    get 'Returns the estate-wide fixity (integrity) report' do
      tags        'Preservation'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Coverage-first integrity report. The headline figure is the proportion
        of stored versions that have *any* verification evidence behind them,
        not how many checks happened to run overnight.

        `unverifiable` counts versions that were ingested without a checksum:
        they can never pass and are a coverage gap to close, not a fault.
      DESC

      response '200', 'report generated' do
        before { sign_in admin_user }

        schema type: :object,
               properties: {
                 coverage: {
                   type: :object,
                   properties: {
                     verifiable:       { type: :integer, description: 'Versions with both a digest and a path' },
                     unverifiable:     { type: :integer, description: 'Stored versions with no digest recorded at ingest' },
                     checked:          { type: :integer },
                     never_checked:    { type: :integer },
                     stale:            { type: :integer, description: 'Checked, but outside the recheck window' },
                     due_now:          { type: :integer },
                     coverage_percent: { type: :number },
                     oldest_check_at:  { type: :string, format: 'date-time', nullable: true },
                     by_status:        { type: :object },
                   },
                 },
                 recent_failures: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:                { type: :string, format: :uuid },
                       asset_id:          { type: :string, format: :uuid },
                       asset_version_id:  { type: :string, format: :uuid },
                       status:            { type: :string, enum: %w[failed missing] },
                       storage_path:      { type: :string, nullable: true },
                       storage_backend:   { type: :string, nullable: true },
                       error_message:     { type: :string, nullable: true },
                       checked_at:        { type: :string, format: 'date-time' },
                     },
                   },
                 },
                 last_run_at:        { type: :string, format: 'date-time', nullable: true },
                 checks_last_24h:    { type: :integer },
                 batch_size:         { type: :integer, description: 'Per-run verification budget' },
                 recheck_after_days: { type: :integer },
               }
        run_test!
      end

      response '403', 'administrator privileges required' do
        before { sign_in create(:user, admin: false) }
        run_test!
      end
    end
  end

  # ── POST /api/v1/preservation/verify ─────────────────────────────────────────
  path '/api/v1/preservation/verify' do
    post 'Verifies one asset\'s stored versions on demand' do
      tags        'Preservation'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Re-reads each version's bytes and compares the SHA-256 with the digest
        recorded at ingest. Runs inline because the caller is waiting for the
        answer. Capped at the 25 most recent versions so one request cannot
        trigger unbounded storage egress.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          asset_id: { type: :string, description: 'Asset UUID or primary key' },
        },
        required: [ 'asset_id' ],
      }

      response '200', 'verification complete' do
        before { sign_in admin_user }
        let(:payload) { { asset_id: asset.id } }

        schema type: :object,
               properties: {
                 asset_id: { type: :string, format: :uuid },
                 verified: { type: :integer },
                 skipped:  { type: :integer, description: 'Versions with no digest to compare against' },
                 results: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       version_id:     { type: :string, format: :uuid },
                       version_number: { type: :integer },
                       status:         { type: :string, enum: %w[passed failed missing unreadable unverifiable] },
                       message:        { type: :string, nullable: true },
                       checked_at:     { type: :string, format: 'date-time', nullable: true },
                     },
                   },
                 },
               }
        run_test!
      end

      response '404', 'asset not found' do
        before { sign_in admin_user }
        let(:payload) { { asset_id: SecureRandom.uuid } }
        run_test!
      end
    end
  end

  # ── GET /api/v1/preservation/formats ─────────────────────────────────────────
  path '/api/v1/preservation/formats' do
    get 'Returns the format obsolescence profile of the estate' do
      tags        'Preservation'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Fixity answers "are the bytes still the bytes". This answers the
        question that outlives it: "will anything still be able to read them".
        Formats are sorted riskiest first. An unassessed format is reported as
        `medium` risk with category `unknown` rather than assumed safe.
      DESC

      response '200', 'profile generated' do
        before { sign_in admin_user }

        schema type: :object,
               properties: {
                 formats: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       content_type: { type: :string },
                       risk:         { type: :string, enum: %w[low medium high] },
                       category:     { type: :string },
                       note:         { type: :string },
                       count:        { type: :integer },
                     },
                   },
                 },
                 totals: {
                   type: :object,
                   properties: {
                     assets:           { type: :integer },
                     distinct_formats: { type: :integer },
                     high_risk:        { type: :integer },
                     medium_risk:      { type: :integer },
                     low_risk:         { type: :integer },
                   },
                 },
               }
        run_test!
      end
    end
  end
end
