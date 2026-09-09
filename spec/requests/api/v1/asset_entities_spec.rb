# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Asset Entity Links API', type: :request do
  let(:admin_user) { create(:user, admin: true) }
  let(:linked_asset) { create(:asset, properties: { 'tags' => %w[berlin sunset] }) }
  let(:person) { create(:entity, entity_type: 'person', name: 'Jane Doe') }

  link_schema = {
    type: :object,
    properties: {
      id:       { type: :string, format: :uuid },
      asset_id: { type: :string, format: :uuid },
      entity: {
        type: :object,
        properties: {
          id:          { type: :string, format: :uuid },
          name:        { type: :string },
          entity_type: { type: :string },
          reference:   { type: :string },
        },
      },
      relationship: { type: :string, enum: %w[depicts shot_by belongs_to located_at mentions] },
      source:       { type: :string, enum: %w[manual tag_resolution ai] },
      confidence:   { type: :number, nullable: true, description: 'Machine-derived links only' },
      asserted:     { type: :boolean, description: 'A person stated or agreed with this link' },
      confirmed_at: { type: :string, format: 'date-time', nullable: true },
      confirmed_by: { type: :string, nullable: true },
      created_at:   { type: :string, format: 'date-time' },
    },
  }

  # ── /api/v1/assets/{asset_id}/entities ───────────────────────────────────────
  path '/api/v1/assets/{asset_id}/entities' do
    parameter name: :asset_id, in: :path, schema: { type: :string }, required: true,
              description: 'Asset UUID or primary key'

    get "Lists an asset's entity links" do
      tags     'Entities'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Each link states *how* the asset relates to the entity, which is what
        separates the photographer from the person in the frame.

        `asserted` is the field that matters for any policy decision: a link
        produced by tag resolution or by a model is a proposal about identity,
        and identity is what consent and rights decisions later hang on.
      DESC

      response '200', 'links returned' do
        before { sign_in admin_user }
        let(:asset_id) { linked_asset.id }

        schema type: :object,
               properties: {
                 asset_id: { type: :string, format: :uuid },
                 links:    { type: :array, items: link_schema },
               }
        run_test!
      end

      response '404', 'asset not found' do
        before { sign_in admin_user }
        let(:asset_id) { SecureRandom.uuid }
        run_test!
      end
    end

    post 'Links an asset to an entity' do
      tags     'Entities'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates a human assertion. `source` is forced to `manual` rather than
        taken from the request: a client that could name its own source could
        post a machine guess that arrives already indistinguishable from a
        curator's statement.

        The relationship must be valid for the entity's type — `shot_by` accepts
        only a person. Linking to an entity that has been merged away links to
        the survivor instead.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          entity_id:    { type: :string, format: :uuid },
          relationship: { type: :string, enum: %w[depicts shot_by belongs_to located_at mentions] },
        },
        required: %w[entity_id relationship],
      }

      response '201', 'link created' do
        before { sign_in admin_user }
        let(:asset_id) { linked_asset.id }
        let(:payload) { { entity_id: person.id, relationship: 'shot_by' } }

        schema link_schema
        run_test!
      end

      response '422', 'relationship invalid for the entity type' do
        before { sign_in admin_user }
        let(:asset_id) { linked_asset.id }
        let(:payload) do
          { entity_id: create(:entity, entity_type: 'campaign', name: 'Spring').id, relationship: 'shot_by' }
        end
        run_test!
      end
    end
  end

  # ── POST /api/v1/assets/{asset_id}/entities/resolve ──────────────────────────
  path '/api/v1/assets/{asset_id}/entities/resolve' do
    parameter name: :asset_id, in: :path, schema: { type: :string }, required: true

    post "Proposes entity links from the asset's existing tags" do
      tags     'Entities'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Reads the asset's tags and links the ones that name exactly one known
        entity, matching on entity names and aliases. The tags themselves are
        never modified: they remain the raw record of what somebody typed, so
        the pass can be re-run after the alias table improves.

        A tag matching several entities is reported as `ambiguous` with its
        candidates and is *not* linked. That ambiguity is the exact failure this
        feature exists to fix, and breaking the tie automatically would
        reintroduce it one layer up and much harder to see.

        Every link created here is unconfirmed.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { dry_run: { type: :boolean, description: 'Report what would happen without writing' } },
      }

      response '200', 'resolution complete' do
        before { sign_in admin_user }
        let(:asset_id) { linked_asset.id }
        let(:payload) { { dry_run: true } }

        schema type: :object,
               properties: {
                 asset_id: { type: :string, format: :uuid },
                 dry_run:  { type: :boolean },
                 linked: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       tag:          { type: :string },
                       entity_id:    { type: :string, format: :uuid },
                       entity_name:  { type: :string },
                       entity_type:  { type: :string },
                       relationship: { type: :string },
                     },
                   },
                 },
                 ambiguous: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       tag: { type: :string },
                       candidates: {
                         type: :array,
                         items: {
                           type: :object,
                           properties: {
                             id:          { type: :string, format: :uuid },
                             name:        { type: :string },
                             entity_type: { type: :string },
                           },
                         },
                       },
                     },
                   },
                 },
                 unmatched: { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  # ── POST /api/v1/asset_entities/{id}/confirm ─────────────────────────────────
  path '/api/v1/asset_entities/{id}/confirm' do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post 'Confirms a machine-derived link' do
      tags     'Entities'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Records human agreement with a proposal. `source` is left as it was, so
        the record still shows where the claim came from; `asserted` becomes
        true, which is what policy consumers read.
      DESC

      response '200', 'link confirmed' do
        before { sign_in admin_user }
        let(:id) { create(:asset_entity, :from_ai, asset: linked_asset).id }

        schema link_schema
        run_test!
      end

      response '404', 'link not found' do
        before { sign_in admin_user }
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  # ── DELETE /api/v1/asset_entities/{id} ───────────────────────────────────────
  path '/api/v1/asset_entities/{id}' do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true

    delete 'Removes a link' do
      tags     'Entities'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Removes the claim only. The entity itself is untouched.'

      response '204', 'link removed' do
        before { sign_in admin_user }
        let(:id) { create(:asset_entity, asset: linked_asset).id }
        run_test!
      end
    end
  end
end
