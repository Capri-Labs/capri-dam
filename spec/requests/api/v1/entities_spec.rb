# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Entities API', type: :request do
  let(:admin_user) { create(:user, admin: true) }
  let(:entity)     { create(:entity, entity_type: 'brand', name: 'Volkswagen') }

  entity_schema = {
    type: :object,
    properties: {
      id:          { type: :string, format: :uuid },
      entity_type: { type: :string, enum: %w[person product place campaign brand event] },
      name:        { type: :string },
      slug:        { type: :string, description: 'Unique within the entity type, not globally' },
      reference:   { type: :string, description: 'Qualified form used in search filters, e.g. "person:jane-doe"' },
      description: { type: :string, nullable: true },
      asset_count: { type: :integer },
      created_at:  { type: :string, format: 'date-time' },
    },
  }

  # ── GET /api/v1/entities/vocabulary ──────────────────────────────────────────
  path '/api/v1/entities/vocabulary' do
    get 'Returns the entity types and the relationships each may hold' do
      tags        'Entities'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Served rather than hardcoded in the client, for the same reason the
        search field registry is: a client-side copy eventually offers a
        combination the server rejects, and the failure then looks like a bug in
        the user's input rather than a stale constant.

        Note that `shot_by` accepts only `person`. A campaign did not take the
        photograph, and allowing it would put nonsense in the index.
      DESC

      response '200', 'vocabulary returned' do
        before { sign_in admin_user }

        schema type: :object,
               properties: {
                 entity_types: { type: :array, items: { type: :string } },
                 relationships: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       name:         { type: :string },
                       label:        { type: :string },
                       entity_types: { type: :array, items: { type: :string } },
                     },
                   },
                 },
                 sources: { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  # ── GET/POST /api/v1/entities ────────────────────────────────────────────────
  path '/api/v1/entities' do
    get 'Lists entities' do
      tags     'Entities'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Searches names and aliases. Entities merged into another are never listed.'

      parameter name: :entity_type, in: :query, schema: { type: :string }, required: false
      parameter name: :q,           in: :query, schema: { type: :string }, required: false,
                description: 'Matches the name or any alias'
      parameter name: :limit,       in: :query, schema: { type: :integer }, required: false
      parameter name: :offset,      in: :query, schema: { type: :integer }, required: false

      response '200', 'entities returned' do
        before { sign_in admin_user }
        let(:entity_type) { nil }
        let(:q) { nil }
        let(:limit) { nil }
        let(:offset) { nil }

        schema type: :object,
               properties: {
                 entities: { type: :array, items: entity_schema },
                 total:    { type: :integer },
               }
        run_test!
      end
    end

    post 'Creates an entity' do
      tags     'Entities'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        The slug is derived from the name unless supplied, and is unique
        *within* a type. "berlin" the place and "berlin" the campaign are
        different entities and both may hold the obvious slug — which is the
        distinction that plain tags cannot express.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          entity: {
            type: :object,
            properties: {
              entity_type:  { type: :string, enum: %w[person product place campaign brand event] },
              name:         { type: :string },
              slug:         { type: :string, description: 'Optional; derived from the name when omitted' },
              description:  { type: :string },
              properties:   { type: :object, description: 'Type-specific attributes (SKU, coordinates, dates)' },
              external_ids: { type: :object, description: 'Identifiers in other systems, for later reconciliation' },
            },
            required: %w[entity_type name],
          },
          aliases: { type: :array, items: { type: :string }, description: 'Other strings that mean this entity' },
        },
        required: [ 'entity' ],
      }

      response '201', 'entity created' do
        before { sign_in admin_user }
        let(:payload) { { entity: { entity_type: 'brand', name: 'Volkswagen' }, aliases: [ 'VW' ] } }
        run_test!
      end

      response '422', 'validation failed' do
        before { sign_in admin_user }
        let(:payload) { { entity: { entity_type: 'spaceship', name: 'Nope' } } }
        run_test!
      end
    end
  end

  # ── /api/v1/entities/{id} ────────────────────────────────────────────────────
  path '/api/v1/entities/{id}' do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get 'Returns one entity with its aliases and link counts' do
      tags     'Entities'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'entity returned' do
        before { sign_in admin_user }
        let(:id) { entity.id }
        run_test!
      end

      response '404', 'entity not found' do
        before { sign_in admin_user }
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end

    patch 'Updates an entity' do
      tags     'Entities'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        `entity_type` is ignored if sent. Changing it would reclassify every
        existing link in one write — a "shot_by person" would silently become a
        "shot_by campaign", which the relationship matrix forbids on creation
        but cannot retroactively undo. Reclassifying means creating the right
        entity and merging into it, which leaves a trail.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { entity: { type: :object } },
      }

      response '200', 'entity updated' do
        before { sign_in admin_user }
        let(:id) { entity.id }
        let(:payload) { { entity: { name: 'Volkswagen AG' } } }
        run_test!
      end
    end

    delete 'Deletes an entity that nothing links to' do
      tags     'Entities'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Refused while links exist. Deleting would strip a claim from every asset
        that carried it, and the link being destroyed is the only record that it
        ever existed. Merge is the operation for a duplicate; deletion is only
        for something created by mistake.
      DESC

      response '204', 'entity deleted' do
        before { sign_in admin_user }
        let(:id) { create(:entity, entity_type: 'place').id }
        run_test!
      end

      response '409', 'entity still has links' do
        before { sign_in admin_user }
        let(:id) do
          linked = create(:entity, entity_type: 'place')
          create(:asset_entity, entity: linked, relationship: 'located_at')
          linked.id
        end
        run_test!
      end
    end
  end

  # ── POST /api/v1/entities/{id}/merge ─────────────────────────────────────────
  path '/api/v1/entities/{id}/merge' do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post 'Merges this entity into another' do
      tags     'Entities'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Duplicates are not a defect; they are what happens when the input is
        prose. The duplicate is kept and made to point at the survivor, so links
        made against it still resolve and the merge stays legible — and
        reversible — after the fact. Its name is adopted as an alias of the
        survivor, or the next resolution pass would simply recreate it.

        Merging across types is refused: it would reclassify every link at once.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { canonical_id: { type: :string, format: :uuid, description: 'The entity that survives' } },
        required: [ 'canonical_id' ],
      }

      response '200', 'entities merged' do
        before { sign_in admin_user }
        let(:id) { create(:entity, entity_type: 'brand', name: 'VW').id }
        let(:payload) { { canonical_id: entity.id } }

        schema type: :object,
               properties: {
                 canonical:       entity_schema,
                 links_moved:     { type: :integer },
                 links_discarded: { type: :integer, description: 'Claims both entities already carried' },
                 aliases_moved:   { type: :integer },
               }
        run_test!
      end

      response '422', 'merge refused' do
        before { sign_in admin_user }
        let(:id) { create(:entity, entity_type: 'place', name: 'Wolfsburg').id }
        let(:payload) { { canonical_id: entity.id } }
        run_test!
      end
    end
  end

  # ── POST /api/v1/entities/{id}/aliases ───────────────────────────────────────
  path '/api/v1/entities/{id}/aliases' do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post 'Adds an alias' do
      tags     'Entities'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Aliases are how resolution reaches the library's existing vocabulary:
        "VW", "Volkswagen" and "volkswagen ag" are one brand. Stored normalised
        (lowercased, whitespace collapsed).

        The same alias may belong to several entities. That ambiguity is real
        and is surfaced by the resolver rather than resolved arbitrarily.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { alias_text: { type: :string } },
        required: [ 'alias_text' ],
      }

      response '201', 'alias added' do
        before { sign_in admin_user }
        let(:id) { entity.id }
        let(:payload) { { alias_text: 'VW' } }
        run_test!
      end
    end
  end
end
