# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Collections', type: :request do
  # ===========================================================================
  # INDEX — GET /api/v1/collections
  # ===========================================================================
  path '/api/v1/collections' do
    get 'List all active collections / workspaces' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns all active (non-archived) collections ordered by `created_at DESC`.
        Supports **temporal time-travel** via `as_of`: pass an ISO-8601 timestamp
        to see what collections existed at that point in time.
        Pass `asset_id` to receive `pinned_for_asset: true/false` for each collection,
        indicating whether the asset is currently pinned to that collection.
      DESC

      parameter name: :as_of, in: :query, type: :string, required: false,
                description: 'ISO-8601 datetime for temporal filtering (e.g. `2025-01-15T00:00:00Z`)'
      parameter name: :asset_id, in: :query, type: :string, required: false,
                description: 'UUID of an asset — when provided, each collection includes `pinned_for_asset: true/false`'

      response '200', 'Collections returned' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id:                { type: :integer },
                   name:              { type: :string, example: 'Q3 Brand Campaign' },
                   slug:              { type: :string, example: 'q3-brand-campaign' },
                   description:       { type: :string, nullable: true },
                   collection_type:   { type: :string, example: 'smart',
                                        description: 'manual | smart' },
                   assets_count:      { type: :integer, example: 24 },
                   pinned_for_asset:  { type: :boolean, nullable: true,
                                        description: 'Included only when asset_id is provided' },
                   expires_at:        { type: :string, format: 'date-time', nullable: true },
                   created_at:        { type: :string, format: 'date-time' },
                 },
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    post 'Create a new collection / workspace' do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'collection' ],
        properties: {
          collection: {
            type: :object,
            required: [ 'name' ],
            properties: {
              name:            { type: :string,  example: 'Q3 Brand Campaign' },
              description:     { type: :string,  nullable: true },
              collection_type: { type: :string,  example: 'manual',
                                 description: 'manual | smart' },
              expires_at:      { type: :string,  format: 'date-time', nullable: true },
              properties: {
                type: :object,
                properties: {
                  tags:           { type: :array,  items: { type: :string }, example: [ 'brand', 'social' ] },
                  allowed_groups: { type: :array,  items: { type: :string }, example: [ 'marketing' ] },
                  denied_groups:  { type: :array,  items: { type: :string } },
                },
              },
            },
          },
        },
      }

      response '201', 'Collection created' do
        schema type: :object, properties: { id: { type: :integer }, slug: { type: :string } }
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
  # BULK DELETE — DELETE /api/v1/collections/bulk_delete
  # ===========================================================================
  path '/api/v1/collections/bulk_delete' do
    delete 'Bulk soft-delete (archive) multiple collections' do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'ids' ],
        properties: {
          ids: { type: :array, items: { type: :integer }, example: [ 1, 2, 3 ] },
        },
      }

      response '200', 'Collections archived' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '400', 'No IDs provided' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # BULK UPDATE — PATCH /api/v1/collections/bulk_update
  # ===========================================================================
  path '/api/v1/collections/bulk_update' do
    patch 'Bulk update metadata/properties across multiple collections' do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Deep-merges the provided `properties` into each matching collection's
        existing JSONB properties. Top-level scalar fields (e.g. `expires_at`)
        are overwritten directly.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'ids' ],
        properties: {
          ids:        { type: :array,  items: { type: :integer }, example: [ 1, 2 ] },
          expires_at: { type: :string, format: 'date-time', nullable: true },
          properties: {
            type: :object,
            properties: {
              tags: { type: :array, items: { type: :string } },
            },
          },
        },
      }

      response '200', 'Collections updated' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '400', 'No IDs provided' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '500', 'Internal server error' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SIMULATE RULE — POST /api/v1/collections/simulate_rule
  # ===========================================================================
  path '/api/v1/collections/simulate_rule' do
    post 'Simulate a smart-collection rule without saving it' do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Runs either a real metadata-filter match (against actual asset
        `properties`) or a mocked pgvector cosine-similarity search against a
        semantic prompt, and returns matching assets with match scores. Use
        this to preview the results of a smart-collection rule **before**
        committing it. Provide `metadata_filters` for a real (non-mocked)
        preview, or `semantic_prompt` for the AI-gateway mock.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          semantic_prompt:      { type: :string,  example: 'outdoor lifestyle photography autumn' },
          similarity_threshold: { type: :number,  example: 0.80,
                                  description: 'Cosine similarity floor (0.0–1.0)' },
          metadata_filters:     { type: :object, example: { status: 'approved' },
                                  description: 'Real (non-mocked) property match preview; matches assets whose properties intersect these values' },
        },
      }

      response '200', 'Simulation results returned' do
        schema type: :object,
               properties: {
                 matches: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:               { type: :integer },
                       title:            { type: :string },
                       properties:       { type: :object },
                       mock_match_score: { type: :number, example: 0.923 },
                     },
                   },
                 },
                 count:   { type: :integer },
                 message: { type: :string, example: 'Simulation complete.' },
               }
        run_test!
      end

      response '400', 'Missing both `semantic_prompt` and `metadata_filters` parameters' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW — GET /api/v1/collections/{slug}
  # ===========================================================================
  path '/api/v1/collections/{slug}' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'URL-safe slug identifier for the collection'

    get 'Retrieve a collection with its assets and smart-rule config' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns full collection details including nested assets (respecting
        `as_of` time-travel), the `collection_rule` config, and any compliance
        violations detected on asset metadata.
      DESC

      parameter name: :as_of, in: :query, type: :string, required: false,
                description: 'ISO-8601 datetime — only show assets that were in the collection at this point'

      response '200', 'Collection details returned' do
        schema type: :object,
               properties: {
                 id:                   { type: :integer },
                 name:                 { type: :string },
                 slug:                 { type: :string },
                 collection_type:      { type: :string },
                 compliance_violations: { type: :array, items: { type: :object } },
                 collection_rule: {
                   type: :object,
                   nullable: true,
                   properties: {
                     semantic_prompt:      { type: :string },
                     similarity_threshold: { type: :number },
                     metadata_filters:     { type: :object },
                     active:               { type: :boolean },
                   },
                 },
                 collection_assets: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       pinned: { type: :boolean },
                       asset: {
                         type: :object,
                         properties: {
                           id:         { type: :integer },
                           title:      { type: :string },
                           properties: { type: :object },
                           created_at: { type: :string, format: 'date-time' },
                         },
                       },
                     },
                   },
                 },
               }
        run_test!
      end

      response '403', 'Unauthorized — user does not have clearance for this workspace' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Collection not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    patch 'Update a collection' do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'collection' ],
        properties: {
          collection: {
            type: :object,
            properties: {
              name:        { type: :string },
              description: { type: :string, nullable: true },
              expires_at:  { type: :string, format: 'date-time', nullable: true },
              properties: {
                type: :object,
                properties: {
                  tags:           { type: :array, items: { type: :string } },
                  allowed_groups: { type: :array, items: { type: :string } },
                  denied_groups:  { type: :array, items: { type: :string } },
                },
              },
            },
          },
        },
      }

      response '200', 'Collection updated' do
        run_test!
      end

      response '404', 'Collection not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'Validation failed' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    delete 'Archive (soft-delete) a collection' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Sets `deleted_at` on the collection to preserve audit trails.'

      response '200', 'Collection archived' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '404', 'Collection not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # CLUSTER MAP — GET /api/v1/collections/{slug}/cluster_map
  # ===========================================================================
  path '/api/v1/collections/{slug}/cluster_map' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'Collection slug'

    get 'Retrieve 2D UMAP/t-SNE cluster coordinates for collection assets' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns 2D `[x, y]` projections for each asset in the collection for
        cluster-map visualisation. In production, coordinates are generated by a
        Python FastAPI gateway running UMAP/t-SNE on 1536-dim pgvector embeddings.
      DESC

      response '200', 'Cluster map nodes returned' do
        schema type: :object,
               properties: {
                 nodes: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:    { type: :integer },
                       title: { type: :string },
                       x:     { type: :number, example: 42.73 },
                       y:     { type: :number, example: 18.56 },
                       url:   { type: :string, nullable: true },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # CONFIGURE SMART RULE — POST /api/v1/collections/{slug}/rule
  # ===========================================================================
  path '/api/v1/collections/{slug}/rule' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'Collection slug'

    post 'Configure or update the smart-routing rule for a collection' do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Upserts the `CollectionRule` for this workspace. Setting `active: true`
        causes the system to automatically route assets that match the
        configured rule into this collection. Also marks the collection as
        `collection_type: smart`. Requires administrative (collection-admin)
        access to the workspace.

        `match_mode` selects the routing strategy:
        - `semantic` (default) — AI cosine-similarity match against `semantic_prompt`
        - `metadata` — pure property/tag match against `metadata_filters`, no AI involved
        - `hybrid` — both must pass
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          match_mode:           { type: :string, enum: %w[semantic metadata hybrid], example: 'semantic' },
          semantic_prompt:      { type: :string, example: 'outdoor lifestyle photography' },
          similarity_threshold: { type: :number, example: 0.80 },
          metadata_filters:     { type: :object, example: { region: 'EMEA' } },
          active:               { type: :boolean, example: true },
        },
      }

      response '200', 'Smart rule updated' do
        schema type: :object,
               properties: {
                 message:    { type: :string },
                 collection: { type: :object },
               }
        run_test!
      end

      response '403', 'Caller lacks administrative access to this workspace' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'Rule validation failed' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # ACCESS GOVERNANCE POLICIES — /api/v1/collections/{slug}/policies
  # ===========================================================================
  path '/api/v1/collections/{slug}/policies' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'Collection slug'

    get 'List group-scoped access policies for a collection' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns every `CollectionPolicy` configured for this workspace's
        "Access Governance" tab. An empty array means the collection is still
        on legacy open/allow-list access (`allowed_groups`/`denied_groups`).
      DESC

      response '200', 'Policies returned' do
        schema type: :object,
               properties: {
                 policies: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:            { type: :integer },
                       group_id:      { type: :integer },
                       group_name:    { type: :string },
                       view_access:   { type: :boolean },
                       edit_access:   { type: :boolean },
                       admin_access:  { type: :boolean },
                       explicit_deny: { type: :boolean },
                     },
                   },
                 },
               }
        run_test!
      end
    end

    post "Upsert a group's access tier (viewer/editor/collection-admin) for this workspace" do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates or updates the `CollectionPolicy` for a group on this
        collection. Requires administrative (collection-admin) access.
        Creating even one policy switches the collection from legacy
        open/allow-list access to strict group-governed access.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'group_id' ],
        properties: {
          group_id:      { type: :integer, example: 42 },
          view_access:   { type: :boolean, example: true },
          edit_access:   { type: :boolean, example: false },
          admin_access:  { type: :boolean, example: false },
          explicit_deny: { type: :boolean, example: false },
        },
      }

      response '200', 'Policy upserted' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 policy:  { type: :object },
               }
        run_test!
      end

      response '403', 'Caller lacks administrative access to this workspace' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Group not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'Policy validation failed' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/api/v1/collections/{slug}/policies/{group_id}' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'Collection slug'
    parameter name: :group_id, in: :path, type: :integer, required: true,
              description: 'UserGroup ID'

    delete "Remove a group's explicit access policy for this workspace" do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Removes the `CollectionPolicy` for a group. Once the last policy for
        a collection is removed, access governance reverts to legacy
        allow/deny-list behavior. Requires administrative access.
      DESC

      response '200', 'Policy removed' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '403', 'Caller lacks administrative access to this workspace' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Policy not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # CDN PURGE — POST /api/v1/collections/{slug}/purge_cdn
  # ===========================================================================
  path '/api/v1/collections/{slug}/purge_cdn' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'Collection slug'

    post 'Trigger a CDN cache invalidation for all assets in this collection' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'CDN invalidation initiated' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHARE LINK — POST /api/v1/collections/{slug}/share_link
  # ===========================================================================
  path '/api/v1/collections/{slug}/share_link' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'Collection slug'

    post 'Mint a time-limited, signed public share link for a collection' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Generates a signed, expiring token (see `Collection#generate_share_token`)
        that grants **read-only, unauthenticated** access to this collection at
        `GET /s/collections/{token}`. No new collection state or database column
        is required — the token is a Rails `signed_id`, so it can be revoked
        implicitly by soft-deleting the collection and cannot be tampered with.
      DESC

      response '200', 'Share link generated' do
        schema type: :object,
               properties: {
                 token:      { type: :string, description: 'Opaque signed token' },
                 url:        { type: :string, format: 'uri', example: 'https://api.yourdam.com/s/collections/eyJf...' },
                 expires_at: { type: :string, format: 'date-time' },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # ADD ASSET — POST /api/v1/collections/{slug}/assets
  # ===========================================================================
  path '/api/v1/collections/{slug}/assets' do
    parameter name: :slug, in: :path, type: :string, required: true,
              description: 'Collection slug'

    post 'Add an asset to a collection' do
      tags 'Collections'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'asset_id' ],
        properties: {
          asset_id: { type: :integer, example: 99 },
        },
      }

      response '200', 'Asset added to collection' do
        schema type: :object,
               properties: {
                 message:    { type: :string },
                 collection: { type: :object },
               }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'Asset already in collection or validation error' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # REMOVE ASSET — DELETE /api/v1/collections/{slug}/assets/{asset_id}
  # ===========================================================================
  path '/api/v1/collections/{slug}/assets/{asset_id}' do
    parameter name: :slug,     in: :path, type: :string,  required: true, description: 'Collection slug'
    parameter name: :asset_id, in: :path, type: :integer, required: true, description: 'Asset ID'

    delete 'Remove an asset from a collection' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'Asset removed from collection' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '404', 'Asset not found in this collection' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    patch 'Toggle the pinned state of an asset within a collection' do
      tags 'Collections'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Toggles `pinned` on the `CollectionAsset` join record. Pinned assets are
        always shown at the top of the collection view. Unpinned assets are
        dynamically positioned by the AI routing engine.
      DESC

      response '200', 'Pin state toggled' do
        schema type: :object,
               properties: {
                 message: { type: :string, example: 'Asset pinned manually.' },
                 pinned:  { type: :boolean },
               }
        run_test!
      end

      response '404', 'Asset not in collection' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
