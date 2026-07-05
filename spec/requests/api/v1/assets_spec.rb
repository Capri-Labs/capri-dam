# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Assets', type: :request do
  # ===========================================================================
  # SEARCH — GET /api/v1/search
  # Routed to SearchController#index (lexical + dynamic metadata filters + facets)
  # ===========================================================================
  path '/api/v1/search' do
    get 'Search assets (lexical + dynamic metadata facets)' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Performs full-text lexical search against asset titles and original filenames.
        Supports dynamic metadata filtering via arbitrary query params (e.g. `?region=EMEA`).
        Returns facet data alongside results so UIs can build filter panels without extra calls.
      DESC

      parameter name: :q,    in: :query, type: :string, required: false,
                description: 'Full-text term matched against title and original_filename'
      parameter name: :mode, in: :query, type: :string, required: false,
                enum: %w[images files videos documents folders visual agentic],
                description: <<~DESC
                  `images` (default), `files`, `videos`, `documents` filter by content type (lexical pipeline).
                  `folders` searches Folder records by name instead of Asset records.
                  `visual` and `agentic` delegate to the pgvector semantic pipeline (AI Gateway embedding +
                  HNSW nearest-neighbour search), falling back to the lexical pipeline if the AI Gateway is
                  unreachable (see `meta.semantic_fallback`).
                DESC

      response '200', 'Search results with facets returned' do
        schema type: :object,
               properties: {
                 meta: {
                   type: :object,
                   properties: {
                     query:       { type: :string, nullable: true, example: 'brand logo' },
                     mode:        { type: :string, example: 'images' },
                     result_type: { type: :string, example: 'asset',
                                    description: '`asset` (default), `folder`, or `semantic`.' },
                     total_found: { type: :integer, example: 47 },
                     semantic_fallback: { type: :boolean, nullable: true,
                                          description: 'true when a visual/agentic query fell back to lexical search' },
                     facets: {
                       type: :object,
                       properties: {
                         content_type: {
                           type: :array, items: { type: :string },
                           example: [ 'image/jpeg', 'image/png' ]
                         },
                       },
                     },
                   },
                 },
                 results: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:        { oneOf: [ { type: :integer }, { type: :string } ], example: 1 },
                       uuid:      { type: :string, format: :uuid, nullable: true },
                       title:     { type: :string, example: 'Brand Logo Final' },
                       type:      { type: :string, example: 'image/png',
                                    description: '`content_type` for assets, or literal `folder` for folder results' },
                       content_type: { type: :string, nullable: true, example: 'image/png' },
                       size:      { type: :string, nullable: true, example: '2.4 MB' },
                       thumb_url: { type: :string, nullable: true,
                                    description: 'Display thumbnail — points at the generated preview variant for formats a browser cannot decode natively (PSD, TIFF, HEIC, RAW, PDF, AI, EPS, …), otherwise the original file.' },
                       preview_url: { type: :string, nullable: true, description: 'Web-renderable preview URL (falls back to the asset URL)' },
                       url:       { type: :string, nullable: true, description: 'Original/raw asset file URL (not the flattened preview)' },
                       web_renderable: { type: :boolean, nullable: true,
                                         description: 'true when content_type can be decoded natively by a browser <img> tag (i.e. thumb_url/preview_url point at the original file, not a generated preview)' },
                       href:      { type: :string, nullable: true, description: 'Direct navigation URL (folder results only)' },
                       similarity_score: { type: :string, nullable: true,
                                           description: '1 - cosine_distance; present only for semantic (visual/agentic) results' },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SEARCH SUGGESTIONS — GET /api/v1/search/suggestions
  # Lightweight autocomplete for the global top-bar search box (Redis-cached)
  # ===========================================================================
  path '/api/v1/search/suggestions' do
    get 'Autocomplete suggestions (mixed assets + folders)' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns a small, fast, Redis-cached list of matching assets and folders for the
        top-bar search-as-you-type dropdown. Designed to be called on every keystroke
        (debounced client-side), so results are capped at 5 assets + 3 folders.
      DESC

      parameter name: :q, in: :query, type: :string, required: false,
                description: 'Prefix term matched against asset titles/filenames and folder names'

      response '200', 'Suggestions returned (may be empty array)' do
        schema type: :object,
               properties: {
                 query: { type: :string, example: 'brand' },
                 results: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       type:      { type: :string, enum: %w[asset folder], example: 'asset' },
                       id:        { oneOf: [ { type: :integer }, { type: :string } ], example: 'a1b2c3d4-...' },
                       title:     { type: :string, example: 'Brand Kit' },
                       subtitle:  { type: :string, nullable: true, example: 'image/png' },
                       thumb_url: { type: :string, nullable: true },
                       href:      { type: :string, example: '/assets?id=a1b2c3d4-...' },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # ASSET CREATION — POST /api/v1/assets
  # ===========================================================================
  path '/api/v1/assets' do
    post 'Upload a new asset (multipart)' do
      tags 'Assets'
      consumes 'multipart/form-data'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Accepts a multipart file and immediately queues async processing
        (`AssetProcessorWorker`, `CdnInvalidationWorker`, `EdgeMetadataSyncWorker`).

        **Lifecycle**: `status: pending` → background workers → `status: ready`.
        Poll `GET /api/v1/assets/{id}/versions` to monitor progress.
      DESC

      parameter name: :file,      in: :formData, type: :string,  format: :binary, required: true,
                description: 'Binary file to upload'
      parameter name: :title,     in: :formData, type: :string,  required: false,
                description: 'Human-readable title; defaults to original filename'
      parameter name: :folder_id, in: :formData, type: :integer, required: false,
                description: 'Destination folder ID; omit to place at root'

      response '202', 'Asset accepted and queued for processing' do
        schema type: :object,
               required: [ 'id', 'status' ],
               properties: {
                 id:     { type: :string, format: :uuid },
                 status: { type: :string, example: 'processing' },
               }
        run_test!
      end

      response '422', 'No file provided' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # ASSET MEMBER — DELETE /api/v1/assets/{id}  (soft delete)
  # ===========================================================================
  path '/api/v1/assets/{id}' do
    parameter name: :id, in: :path, type: :string, required: true,
              description: 'Asset database ID (integer primary key)'

    delete 'Soft-delete an asset (move to Recycle Bin)' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Sets `deleted_at`. Recoverable via restore or permanently via permanent delete.'

      response '200', 'Asset moved to bin' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Moved to bin' },
               }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # RESTORE — POST /api/v1/assets/{id}/restore
  # ===========================================================================
  path '/api/v1/assets/{id}/restore' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    post 'Restore a soft-deleted asset from the Recycle Bin' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'Asset restored to active state' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Asset restored' },
               }
        run_test!
      end

      response '404', 'Asset not found in the bin' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # PERMANENT DELETE — DELETE /api/v1/assets/{id}/permanent
  # ===========================================================================
  path '/api/v1/assets/{id}/permanent' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    delete 'Permanently delete an asset and all its storage versions' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        **Irreversible.** Purges all physical files from the active storage backend
        for every version and destroys the database record. Also triggers an edge
        CDN purge so stale URLs return 404 immediately.
      DESC

      response '200', 'Asset permanently deleted' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Permanently deleted all versions' },
               }
        run_test!
      end

      response '404', 'Asset not found in the bin' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # VERSIONS — GET /api/v1/assets/{id}/versions
  # ===========================================================================
  path '/api/v1/assets/{id}/versions' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    get 'List all immutable versions of an asset' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns the full version chain in descending order. `is_active: true` marks
        the currently published version. To promote a prior version, call
        `POST /api/v1/assets/{id}/versions/{version_id}/restore`.
      DESC

      response '200', 'Version history returned' do
        schema type: :object,
               properties: {
                 versions: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:             { type: :integer },
                       version_number: { type: :integer, example: 3 },
                       action_type:    { type: :string, example: 'Image Edit' },
                       created_at:     { type: :string, example: 'Jun 21, 2026 at 03:15 PM' },
                       created_by:     { type: :string, example: 'ashok@example.com' },
                       is_active:      { type: :boolean },
                       size:           { type: :string, example: '4.20 MB' },
                     },
                   },
                 },
               }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # METADATA SCHEMA — GET /api/v1/assets/{id}/metadata_schema
  # ===========================================================================
  path '/api/v1/assets/{id}/metadata_schema' do
    parameter name: :id, in: :path, type: :string, required: true,
              description: 'Asset database ID or UUID'

    get 'Resolve the metadata schema for a single asset, pre-filled with its values' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Resolves the metadata schema that applies to the asset (its applied schema,
        else its folder's schema, else the MIME-derived default) and returns it with
        every field's `value` pre-filled from the asset's own metadata. Saved edits
        win over values mapped from the file's embedded EXIF/IPTC/XMP metadata. This
        removes the need for the client to know the schema id or map metadata itself.
      DESC

      response '200', 'Resolved schema with pre-filled field values returned' do
        schema type: :object,
               properties: {
                 id:                { type: :integer, example: 2 },
                 name:              { type: :string, example: 'Image' },
                 slug:              { type: :string, example: 'default--image' },
                 applied_schema_id: { type: :integer, example: 2 },
                 asset_id:          { type: :string, example: 'f249c338-2153-45df-aeba-56bd4cad3c3b' },
                 asset_uuid:        { type: :string, example: 'f249c338-2153-45df-aeba-56bd4cad3c3b' },
                 resolved_tabs: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       name: { type: :string, example: 'Basic' },
                       fields: {
                         type: :array,
                         items: {
                           type: :object,
                           properties: {
                             label:           { type: :string, example: 'Title' },
                             field_type:      { type: :string, example: 'text' },
                             map_to_property: { type: :string, example: 'dc:title' },
                             value:           { type: :string, example: 'Sunset over the bay', nullable: true },
                           },
                         },
                       },
                     },
                   },
                 },
               }
        run_test!
      end

      response '404', 'Asset not found or no schema could be resolved' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # AUDIT TRAIL — GET /api/v1/assets/{id}/audit_trail
  # ===========================================================================
  path '/api/v1/assets/{id}/audit_trail' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    get 'Retrieve the compliance audit trail for an asset' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns every version with its raw `properties` JSONB payload for
        compliance audits and delta-diff calculations — exposing full metadata state
        at each point in time.
      DESC

      response '200', 'Audit trail returned' do
        schema type: :object,
               properties: {
                 audit_trail: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:             { type: :integer },
                       version_number: { type: :integer },
                       action_type:    { type: :string },
                       created_at:     { type: :string, format: 'date-time' },
                       created_by_id:  { type: :integer, nullable: true },
                       properties:     { type: :object,
                                         description: 'Raw JSONB metadata snapshot at this version' },
                     },
                   },
                 },
               }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # RESTORE VERSION — POST /api/v1/assets/{id}/versions/{version_id}/restore
  # ===========================================================================
  path '/api/v1/assets/{id}/versions/{version_id}/restore' do
    parameter name: :id,         in: :path, type: :string, required: true, description: 'Asset ID'
    parameter name: :version_id, in: :path, type: :string, required: true,
              description: 'AssetVersion database ID to promote as active'

    post 'Promote a previous version to the active/published state' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Non-destructive promotion — only updates the `active_version_id` pointer.
        No data is mutated. The CDN URL will serve the restored version on the next
        request (or immediately after a CDN purge).
      DESC

      response '200', 'Version promoted to active' do
        schema type: :object,
               properties: {
                 id:       { type: :integer },
                 uuid:     { type: :string, format: :uuid },
                 title:    { type: :string },
                 version:  { type: :integer, example: 2 },
                 metadata: { type: :object },
                 url:      { type: :string, nullable: true },
               }
        run_test!
      end

      response '404', 'Asset or version not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # PROCESS IMAGE — POST /api/v1/assets/{id}/process_image
  # ===========================================================================
  path '/api/v1/assets/{id}/process_image' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    post 'Apply non-destructive image edits via the baking pipeline' do
      tags 'Assets'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Runs the **Image Baking Pipeline** (ImageMagick/MiniMagick).

        **Save Modes**:
        - `version` — creates a new immutable version on the same asset (default)
        - `overwrite` — replaces the active version in-place (**destructive**)
        - `new` — forks the asset as an independent copy (`title (Copy)`)

        When `target_folder_id` differs from the current folder and `save_mode` is
        `version` or `new`, the result is placed in that target folder.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          save_mode: {
            type: :string,
            enum: [ 'version', 'overwrite', 'new' ],
            example: 'version',
          },
          target_folder_id: {
            type: :string, nullable: true, example: '42',
            description: 'Destination folder ID, or "root"'
          },
          adjustments: {
            type: :object,
            properties: {
              brightness: { type: :integer, example: 10 },
              contrast:   { type: :integer, example: 5 },
              saturation: { type: :integer, example: -20 },
            },
          },
          geometry: {
            type: :object,
            properties: {
              rotate:          { type: :integer, example: 90 },
              flip_horizontal: { type: :boolean, example: false },
              focal_point: {
                type: :object,
                properties: {
                  x: { type: :number, example: 50.0 },
                  y: { type: :number, example: 50.0 },
                },
              },
            },
          },
          filter:     { type: :string, nullable: true, example: 'None' },
          custom_cli: {
            type: :string, nullable: true,
            example: '-monochrome -charcoal 2',
            description: 'Raw ImageMagick CLI flags. Use with caution.'
          },
        },
      }

      response '200', 'Image baked — overwrite or in-place version save' do
        schema type: :object,
               properties: {
                 id: { type: :integer }, uuid: { type: :string, format: :uuid },
                 title: { type: :string }, version: { type: :integer },
                 metadata: { type: :object }, url: { type: :string, nullable: true }
               }
        run_test!
      end

      response '201', 'Fork created — new asset or branch to target folder' do
        schema type: :object,
               properties: {
                 id: { type: :integer }, uuid: { type: :string, format: :uuid },
                 title: { type: :string, example: 'Brand Logo Final (Copy)' },
                 version: { type: :integer }, metadata: { type: :object },
                 url: { type: :string, nullable: true }
               }
        run_test!
      end

      response '422', 'Source file missing from disk' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # WORKFLOW HISTORY — GET /api/v1/assets/{id}/workflow_history
  # ===========================================================================
  path '/api/v1/assets/{id}/workflow_history' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    get 'Retrieve the active workflow instance and task timeline for an asset' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'Workflow history returned (active or inactive)' do
        schema type: :object,
               properties: {
                 active:          { type: :boolean, example: true },
                 instance_status: { type: :string, nullable: true, example: 'in_progress' },
                 started_at:      { type: :string, format: 'date-time', nullable: true },
                 tasks: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:              { type: :integer },
                       step_name:       { type: :string, example: 'Brand Review' },
                       user_name:       { type: :string, example: 'reviewer@example.com' },
                       status:          { type: :string, example: 'pending' },
                       comment:         { type: :string, nullable: true },
                       completed_at:    { type: :string, format: 'date-time', nullable: true },
                       is_current_user: { type: :boolean },
                       is_pending:      { type: :boolean },
                     },
                   },
                 },
               }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # WATERMARKED PROXY — GET /api/v1/assets/{id}/watermarked
  # ===========================================================================
  path '/api/v1/assets/{id}/watermarked' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    get 'Download a watermarked secure proxy of an image asset' do
      tags 'Assets'
      produces 'image/jpeg'
      security [ Bearer: [] ]
      description <<~DESC
        Returns the active image version with a diagonal `CONFIDENTIAL` watermark
        at 40% opacity as a downloadable JPEG attachment.
        Only supported for `image/*` content types.
      DESC

      response '200', 'Watermarked image binary returned as attachment' do
        run_test!
      end

      response '422', 'Asset is not an image type' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '500', 'Image processing pipeline failed (MiniMagick error)' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # USAGE STATISTICS — GET /api/v1/assets/{id}/stats
  # ===========================================================================
  path '/api/v1/assets/{id}/stats' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    get 'Usage statistics for an asset (views/downloads/shares)' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns app-observed usage counters for this asset, backed by the
        {AssetUsageEvent} table (see `Asset#usage_stats`). These reflect events that
        flow through this app (viewer opened, download initiated, link
        copied) — not raw CDN edge hits.
      DESC

      response '200', 'Usage statistics returned' do
        schema type: :object,
               properties: {
                 views:     { type: :integer, example: 12 },
                 downloads: { type: :integer, example: 4 },
                 shares:    { type: :integer, example: 1 },
               }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # TRACK USAGE EVENT — POST /api/v1/assets/{id}/track_event
  # ===========================================================================
  path '/api/v1/assets/{id}/track_event' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Asset ID'

    post 'Record a view/download/share event for an asset' do
      tags 'Assets'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Records a single usage event (`view`, `download`, or `share`) as an
        {AssetUsageEvent} row and returns the updated counters. Called by the
        frontend at the moment the user initiates the action, since the
        actual bytes are often served straight from the CDN/S3 in production
        (see `AssetUrlHelper#asset_url_for`).
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'event' ],
        properties: {
          event: { type: :string, enum: %w[view download share], example: 'view' },
        },
      }

      response '200', 'Event recorded; updated statistics returned' do
        schema type: :object,
               properties: {
                 views:     { type: :integer, example: 12 },
                 downloads: { type: :integer, example: 4 },
                 shares:    { type: :integer, example: 1 },
               }
        let(:payload) { { event: 'view' } }
        run_test!
      end

      response '422', 'Unsupported event name' do
        schema type: :object, properties: { error: { type: :string } }
        let(:payload) { { event: 'bogus' } }
        run_test!
      end

      response '404', 'Asset not found' do
        let(:id) { 'not-a-real-id' }
        let(:payload) { { event: 'view' } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # CHECK HASHES — POST /api/v1/assets/check_hashes
  # ===========================================================================
  path '/api/v1/assets/check_hashes' do
    post 'Pre-upload duplicate detection via SHA-256 checksums' do
      tags 'Assets'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Compute SHA-256 checksums client-side **before** uploading, then call this
        endpoint to detect existing duplicates. Returns matching asset details so
        the UI can warn the user before creating redundant copies.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'hashes' ],
        properties: {
          hashes: {
            type: :array,
            items: { type: :string },
            example: [ 'a1b2c3d4e5f6...', 'e5f6g7h8i9j0...' ],
            description: 'Array of SHA-256 hex strings to check',
          },
        },
      }

      response '200', 'Duplicate check complete (empty `duplicates` object when none found)' do
        schema type: :object,
               properties: {
                 duplicates: {
                   type: :object,
                   description: 'Key = SHA-256 hash; value = array of matching asset records',
                   additionalProperties: {
                     type: :array,
                     items: {
                       type: :object,
                       properties: {
                         id:         { type: :string, format: :uuid },
                         title:      { type: :string },
                         version:    { type: :integer },
                         url:        { type: :string, nullable: true },
                         folderName: { type: :string, example: '/Marketing/Campaigns' },
                       },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # RECYCLE BIN — GET /api/v1/bin
  # ===========================================================================
  path '/api/v1/bin' do
    get 'List all soft-deleted assets and folders in the Recycle Bin' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'Recycle bin contents returned' do
        schema type: :object,
               properties: {
                 folders: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:         { type: :integer },
                       name:       { type: :string },
                       deleted_at: { type: :string, format: 'date-time' },
                     },
                   },
                 },
                 assets: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:           { type: :integer },
                       title:        { type: :string },
                       status:       { type: :string },
                       deleted_at:   { type: :string, format: 'date-time' },
                       properties:   { type: :object },
                       content_type: { type: :string, nullable: true, example: 'image/jpeg' },
                       url:          { type: :string, nullable: true },
                       editable:     { type: :boolean, description: 'Whether the Image Editor can load this asset directly (false for formats like PSD/TIFF/RAW that browsers cannot render natively)' },
                     },
                   },
                 },
                 breadcrumbs: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:   { type: :string, example: 'bin' },
                       name: { type: :string, example: 'Trash Bin' },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SERVE LOCAL FILE — GET /api/v1/assets/local/{uuid}
  # ===========================================================================
  path '/api/v1/assets/local/{uuid}' do
    parameter name: :uuid, in: :path, type: :string, format: :uuid, required: true,
              description: 'Asset UUID (public identifier — **not** the integer PK)'
    parameter name: :variant, in: :query, type: :string, required: false,
              enum: %w[preview],
              description: 'When set to `preview`, streams the generated web-renderable ' \
                           'preview (e.g. a flattened PNG for a PSD/TIFF) instead of the ' \
                           'original binary.'

    get 'Stream the active-version file from local/staging storage' do
      tags 'Assets'
      produces '*/*'
      security [ Bearer: [] ]
      description <<~DESC
        **Development & staging use only.**

        Resolves the UUID to the asset's active version and streams the physical
        binary with the correct `Content-Type`.  In production, assets are served
        via the CDN URL returned in the `url` field of every asset response.

        ### Resolution order
        1. **ActiveStorage attachment** on the active version → `302 Found` to the
           signed blob URL.
        2. **`storage/dam/<relative_path>`** — files moved here by
           `AssetProcessorWorker` after ingestion.
        3. **`tmp/uploads/<uuid>_v1_<filename>`** — files awaiting worker
           processing (staging path).

        ### HTTP caching
        Responses include `ETag` (MD5 of the file) and `Last-Modified` headers.
        Clients that re-send `If-None-Match` receive `304 Not Modified` without
        re-transmitting the body — recommended for thumbnail-heavy list views.

        ### Security
        Both resolved paths are validated against their permitted roots
        (`storage/dam` and `tmp/`) to prevent directory-traversal attacks.
      DESC

      response '200', 'File streamed inline' do
        schema type: :string, format: :binary
        header 'ETag',          schema: { type: :string },  description: 'MD5 fingerprint of the file'
        header 'Last-Modified', schema: { type: :string },  description: 'RFC 7231 last-modified date'
        header 'Cache-Control', schema: { type: :string },  description: 'private, max-age=3600, must-revalidate'
        header 'Content-Type',  schema: { type: :string },  description: 'MIME type of the asset'
        run_test!
      end

      response '302', 'Redirected to ActiveStorage signed blob URL' do
        description 'Issued when the active version has an ActiveStorage attachment.'
        run_test!
      end

      response '304', 'Not Modified — client already has the current version' do
        description 'Returned when `If-None-Match` matches the current `ETag`. No body is sent.'
        run_test!
      end

      response '403', 'Forbidden — resolved path escapes the permitted storage root' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Asset not found or file missing from disk' do
        schema type: :object,
               required: [ 'error' ],
               properties: {
                 error:     { type: :string },
                 looked_at: { type: :string, nullable: true,
                              description: 'Absolute path that was checked' },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # VECTOR EMBEDDING — PUT /api/v1/assets/{asset_id}/embedding
  # (Internal AI Gateway callback — called by Python microservice)
  # ===========================================================================
  path '/api/v1/assets/{asset_id}/embedding' do
    parameter name: :asset_id, in: :path, type: :string, required: true, description: 'Asset ID'

    put 'Upsert pgvector embedding for an asset (AI Gateway callback)' do
      tags 'Assets'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        **Internal microservice endpoint.** Called by the Python AI Gateway after
        computing the vector embedding. Stores the result in `asset_embeddings`
        for HNSW nearest-neighbour semantic search via pgvector.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'asset_embedding' ],
        properties: {
          asset_embedding: {
            type: :object,
            required: [ 'embedding', 'model_name' ],
            properties: {
              embedding:  {
                type: :array, items: { type: :number },
                example: [ 0.023, -0.114, 0.987 ],
                description: '1536-dimension float vector'
              },
              model_name: { type: :string, example: 'text-embedding-ada-002' },
            },
          },
        },
      }

      response '200', 'Vector spatial index updated' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end

      response '422', 'Validation error' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end
end

RSpec.describe 'Image Processing Tests', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:folder) { create(:folder, user: user) }
  let(:test_image_path) { Rails.root.join('spec/fixtures/images/test-image.jpg').to_s }

  before(:all) do
    # Create test image fixture with valid JPEG data
    fixtures_dir = Rails.root.join('spec/fixtures/images')
    FileUtils.mkdir_p(fixtures_dir) unless Dir.exist?(fixtures_dir)

    test_image = Rails.root.join('spec/fixtures/images/test-image.jpg')
    unless File.exist?(test_image)
      # Use ImageMagick's convert command directly via shell
      system("convert -size 100x100 xc:white #{test_image}")
    end
  end

  before do
    sign_in user
  end

  # ===========================================================================
  # IMAGE EDITOR — POST /api/v1/assets/:id/process_image
  # ===========================================================================
  path '/api/v1/assets/{id}/process_image' do
    post 'Process image with adjustments (brightness, contrast, saturation, geometry)' do
      tags 'Assets'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Applies adjustments (brightness, contrast, saturation) and geometric transformations
        (rotation, flips) to an image using the ImageProcessingService. Supports multiple
        save modes: `new` (creates asset), `version` (creates new version), `overwrite` (replaces current).
      DESC

      parameter name: :id, in: :path, type: :string, required: true,
                description: 'Asset UUID'
      parameter name: :adjustments, in: :query, type: :object, required: false,
                schema: {
                  type: :object,
                  properties: {
                    brightness: { type: :integer, example: 20, description: 'Range: -100 to 100' },
                    contrast: { type: :integer, example: -15, description: 'Range: -100 to 100' },
                    saturation: { type: :integer, example: 30, description: 'Range: -100 to 100' },
                  },
                },
                description: 'Image adjustment parameters'
      parameter name: :geometry, in: :query, type: :object, required: false,
                schema: {
                  type: :object,
                  properties: {
                    rotate: { type: :integer, example: 90, description: 'Rotation degrees' },
                    flip_horizontal: { type: :boolean, example: false },
                    flip_vertical: { type: :boolean, example: false },
                    focal_point: {
                      type: :object,
                      properties: {
                        x: { type: :number, example: 50.0 },
                        y: { type: :number, example: 50.0 },
                      },
                    },
                  },
                },
                description: 'Geometric transformation parameters'
      parameter name: :crop_aspect, in: :query, type: :string, required: false,
                example: 'free',
                description: 'Crop aspect ratio (e.g., "free", "16:9", "4:3")'
      parameter name: :filter, in: :query, type: :string, required: false,
                example: 'None',
                description: 'Image filter to apply'
      parameter name: :custom_cli, in: :query, type: :string, required: false,
                description: 'Raw ImageMagick CLI flags (e.g., "-monochrome -charcoal 2")'
      parameter name: :save_mode, in: :query, type: :string, required: false,
                enum: [ 'new', 'version', 'overwrite' ],
                example: 'version',
                description: 'Where to save: `new` (create asset), `version` (new version), `overwrite` (replace)'
      parameter name: :target_folder_id, in: :query, type: :integer, required: false,
                description: 'Folder ID to move output to (save_mode: new only)'

      response '200', 'Image processed and version created' do
        schema type: :object,
               required: [ 'id', 'version' ],
               properties: {
                 id:      { type: :string, format: :uuid },
                 version: { type: :integer, example: 2 },
                 uuid:    { type: :string, format: :uuid },
                 title:   { type: :string },
                 storage_path: { type: :string },
                 file_size: { type: :integer },
               }
        run_test!
      end

      response '201', 'New asset created with processed image (save_mode: new)' do
        schema type: :object,
               required: [ 'id' ],
               properties: {
                 id:   { type: :string, format: :uuid },
                 uuid: { type: :string, format: :uuid },
                 title: { type: :string },
               }
        run_test!
      end

      response '404', 'Asset not found' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Asset not found.' },
               }
        run_test!
      end

      response '422', 'Validation error or source file missing' do
        schema type: :object,
               properties: {
                 error: { type: :string, example: 'Invalid image parameters: brightness must be between -100 and 100' },
               }
        run_test!
      end
    end
  end

  describe 'POST /api/v1/assets/:id/process_image' do
    let!(:asset) do
      create(:asset, user: user, folder: folder, properties: {
        storage_path: test_image_path,
        format: 'jpeg',
      })
    end

    context 'with valid brightness adjustment' do
      it 'processes image with brightness adjustment' do
        payload = {
          save_mode: 'version',
          adjustments: { brightness: 20 },
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to have_key('id')
        expect(json).to have_key('version')
      end
    end

    context 'with contrast adjustment' do
      it 'processes image with contrast adjustment' do
        payload = {
          save_mode: 'version',
          adjustments: { contrast: -15 },
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with saturation adjustment' do
      it 'processes image with saturation adjustment' do
        payload = {
          save_mode: 'version',
          adjustments: { saturation: 30 },
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with rotation' do
      it 'processes image with 90 degree rotation' do
        payload = {
          save_mode: 'version',
          adjustments: {},
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 90, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with flip' do
      it 'processes image with horizontal flip' do
        payload = {
          save_mode: 'version',
          adjustments: {},
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: true },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with filter' do
      it 'processes image with Vivid filter' do
        payload = {
          save_mode: 'version',
          adjustments: {},
          crop_aspect: 'free',
          filter: 'Vivid',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with multiple adjustments' do
      it 'processes image with combined adjustments' do
        payload = {
          save_mode: 'version',
          adjustments: {
            brightness: 10,
            contrast: -5,
            saturation: 20,
            warmth: 15,
          },
          crop_aspect: '16:9',
          filter: 'West',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with save mode version' do
      it 'creates a new version' do
        payload = {
          save_mode: 'version',
          adjustments: { brightness: 10 },
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        expect do
          post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json
        end.to change(AssetVersion, :count).by(1)

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with save mode new' do
      it 'creates a new asset copy' do
        payload = {
          save_mode: 'new',
          target_folder_id: folder.id,
          adjustments: { brightness: 10 },
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        expect do
          post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json
        end.to change(Asset, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end

    context 'with invalid brightness value' do
      it 'returns validation error' do
        payload = {
          save_mode: 'version',
          adjustments: { brightness: 150 },
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json).to have_key('error')
      end
    end

    context 'with invalid crop aspect' do
      it 'returns validation error' do
        payload = {
          save_mode: 'version',
          adjustments: {},
          crop_aspect: 'invalid',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post "/api/v1/assets/#{asset.id}/process_image", params: payload, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with nonexistent asset' do
      it 'returns 404' do
        payload = {
          save_mode: 'version',
          adjustments: {},
          crop_aspect: 'free',
          filter: 'None',
          geometry: { rotate: 0, flip_horizontal: false },
        }

        post '/api/v1/assets/99999/process_image', params: payload, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  private

  def json_headers
    { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
  end
end
