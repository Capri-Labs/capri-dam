# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Folders', type: :request do
  # ===========================================================================
  # INDEX — GET /api/v1/folders
  # ===========================================================================
  path '/api/v1/folders' do
    get 'Retrieve the full folder tree (flat list with paths)' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns every active folder as a flat sorted list with fully-qualified
        path names (e.g. `/Marketing/2026/Campaigns`). Used to populate folder-
        picker dropdowns across the UI. Built in O(n) using a single query + in-
        memory tree traversal — safe for large folder structures.
      DESC

      response '200', 'Folders retrieved successfully' do
        schema type: :object,
               properties: {
                 folders: {
                   type: :array,
                   items: {
                     type: :object,
                     required: [ 'id', 'name' ],
                     properties: {
                       id:        { type: :string, format: :uuid, example: 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d' },
                       name:      { type: :string,  example: '/Marketing/2026' },
                       slug:      { type: :string,  example: 'campaigns' },
                       path:      { type: :string,  example: '/Marketing/2026' },
                       parent_id: { type: :string, nullable: true, example: 'a1b2c3',
                                    description: 'Immediate parent folder ID, or null for a root folder. Used by ' \
                                                 'clients (e.g. AclMatrix) to build a collapsible folder tree.' },
                     },
                   },
                 },
               }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    post 'Create a new folder' do
      tags 'Folders'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'folder' ],
        properties: {
          folder: {
            type: :object,
            required: [ 'name' ],
            properties: {
              name:      { type: :string, example: 'Q3 Campaigns' },
              parent_id: { type: :string, nullable: true, example: 'root',
                           description: 'Parent folder ID or "root" to create at top level' },
            },
          },
        },
      }

      response '201', 'Folder created successfully' do
        let(:payload) { { folder: { name: 'Brand Assets', parent_id: 'root' } } }
        run_test!
      end

      response '422', 'Validation failed (e.g., blank name)' do
        schema type: :object,
               properties: { errors: { type: :array, items: { type: :string } } }
        let(:payload) { { folder: { name: '' } } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW — GET /api/v1/folders/{id}
  # ===========================================================================
  path '/api/v1/folders/{id}' do
    parameter name: :id, in: :path, type: :string, required: true,
              description: 'Folder ID or the string `"root"` to browse the top level'
    parameter name: :sort, in: :query, type: :string, required: false,
              enum: %w[name created_at updated_at size type],
              description: 'Field to sort folders & assets by. Defaults to `name`. ' \
                           '`size` and `type` apply to assets only (folders fall back to `name`).'
    parameter name: :direction, in: :query, type: :string, required: false,
              enum: %w[asc desc],
              description: 'Sort direction. Defaults to `asc`.'

    get 'Retrieve a folder and its direct child contents' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns immediate sub-folders, assets in this folder, and the breadcrumb
        trail back to root. Pass `id=root` to list all top-level items.
        Only active (non-trashed) items are returned.

        Results can be ordered with the `sort` and `direction` query parameters.
        Supported sort fields: `name`, `created_at`, `updated_at`, `size`, `type`.
        Note that `size` and `type` are asset-only fields — folders fall back to
        `name` ordering for those values.
      DESC

      response '200', 'Folder contents returned' do
        schema type: :object,
               properties: {
                 folders: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:          { type: :string, format: :uuid },
                       name:        { type: :string },
                       slug:        { type: :string, nullable: true },
                       description: { type: :string, nullable: true },
                       created_at:  { type: :string, format: 'date-time' },
                       updated_at:  { type: :string, format: 'date-time' },
                       can_modify:  { type: :boolean, description: 'Whether the current user may rename/modify this folder (admins and users with an explicit `modify` grant on it; always true for a nil/root context)' },
                       can_delete:  { type: :boolean, description: 'Whether the current user may remove this folder from its current location (used to gate the Move overlay — admins and users with an explicit `delete` grant on it; always true for a nil/root context)' },
                     },
                   },
                 },
                 assets: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:           { type: :string, format: :uuid },
                       uuid:         { type: :string, format: :uuid },
                       title:        { type: :string },
                       status:       { type: :string, example: 'ready' },
                       version:      { type: :integer },
                       properties:   { type: :object },
                       size:         { type: :integer, description: 'File size in bytes (from active version)' },
                       content_type: { type: :string, nullable: true, example: 'image/jpeg' },
                       created_at:   { type: :string, format: 'date-time' },
                       updated_at:   { type: :string, format: 'date-time' },
                       url:          { type: :string, nullable: true },
                       preview_url:  { type: :string, nullable: true, description: 'Web-renderable preview URL (falls back to the asset URL)' },
                       editable:     { type: :boolean, description: 'Whether the Image Editor can load this asset directly (false for formats like PSD/TIFF/RAW that browsers cannot render natively — see AssetProcessorWorker::WEB_RENDERABLE_MIME_TYPES)' },
                       can_modify:   { type: :boolean, description: 'Whether the current user may rename/modify this asset (based on the `modify` grant on its parent folder; always true for root-level assets with no folder)' },
                       can_delete:   { type: :boolean, description: 'Whether the current user may remove this asset from its current folder (used to gate the Move overlay — based on the `delete` grant on its parent folder; always true for root-level assets)' },
                     },
                   },
                 },
                 breadcrumbs: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:   { type: :string },
                       name: { type: :string },
                     },
                   },
                 },
                 sort: {
                   type: :object,
                   properties: {
                     field:     { type: :string, example: 'name' },
                     direction: { type: :string, example: 'asc' },
                   },
                 },
               }
        let(:id) { 'root' }
        run_test!
      end

      response '404', 'Folder not found or has been deleted' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    patch 'Rename a folder, update its description, and/or move it (parent_id)' do
      tags 'Folders'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Updates the folder `name` (rename), `description`, and/or `parent_id`
        (move). The URL-safe `slug` is regenerated automatically when the name
        changes.

        Renaming/editing the description requires `modify` permission on the
        folder (admins bypass this check). Use `GET /api/v1/folders/{id}` and
        check the `can_modify` flag to decide whether to offer a Rename action.

        Changing `parent_id` is treated as a **Move** and is gated by a
        different rule: it requires `delete` permission on the folder's
        *current* parent and `create` permission on the *destination* folder.
        Set `parent_id` to `"root"` (or omit it) to move to the top level.
        Moving a folder into itself or one of its own descendants is rejected
        with `422`. For moving multiple folders/assets in one request, prefer
        `POST /api/v1/move_operations` instead of calling this endpoint in a
        loop.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'folder' ],
        properties: {
          folder: {
            type: :object,
            properties: {
              name:        { type: :string, example: 'Q4 Campaigns' },
              description: { type: :string, example: 'All creative assets for the Q4 push' },
              parent_id:   { type: :string, nullable: true, example: 'root',
                             description: 'New parent folder ID to move this folder, or "root"/omit to keep it or move to the top level' },
            },
          },
        },
      }

      response '200', 'Folder updated successfully' do
        schema type: :object,
               properties: {
                 id:          { type: :string, format: :uuid },
                 name:        { type: :string },
                 description: { type: :string, nullable: true },
                 slug:        { type: :string, nullable: true },
                 parent_id:   { type: :string, nullable: true },
                 updated_at:  { type: :string, format: 'date-time' },
               }
        run_test!
      end

      response '403', 'Permission denied (modify on the folder, or delete/create for a move)' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'Folder (or destination folder, for a move) not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'Validation failed (e.g., blank name, or a cyclical move)' do
        schema type: :object, properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end

    # --------------------------------------------------------------------------
    delete 'Move a folder to the Recycle Bin (soft delete)' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Soft-deletes the folder by stamping `deleted_at`. A CDN invalidation job
        is dispatched to drop any cached assets under this folder from edge nodes.
        Use `POST /api/v1/folders/{id}/restore` to recover it.
      DESC

      response '200', 'Folder moved to bin' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Folder moved to bin' },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # PROFILES — GET /api/v1/folders/{id}/profiles
  # ===========================================================================
  path '/api/v1/folders/{id}/profiles' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Folder ID'

    get 'Retrieve all configuration profiles assigned to a folder' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns the image processing profile, video encoding profile, metadata
        schema (direct or inherited), and access-control policies assigned to a
        folder. Powers the folder "Info" properties drawer. Any unassigned
        section returns `null`.
      DESC

      response '200', 'Folder profiles returned' do
        schema type: :object,
               properties: {
                 image_profile: {
                   type: :object, nullable: true,
                   properties: {
                     id:                      { type: :integer },
                     name:                    { type: :string },
                     crop_type:               { type: :string },
                     unsharp_mask:            { type: :object, nullable: true },
                     responsive_crop_enabled: { type: :boolean },
                     swatch_enabled:          { type: :boolean },
                   }
                 },
                 video_profile: {
                   type: :object, nullable: true,
                   properties: {
                     id:                            { type: :integer },
                     name:                          { type: :string },
                     description:                   { type: :string, nullable: true },
                     encode_for_adaptive_streaming: { type: :boolean },
                     preset_count:                  { type: :integer },
                   }
                 },
                 metadata_schema: {
                   type: :object, nullable: true,
                   properties: {
                     id:     { type: :integer },
                     name:   { type: :string },
                     source: { type: :string, enum: %w[direct inherited], description: 'Whether the schema is set on this folder or inherited from an ancestor' },
                     tabs:   { type: :array, items: { type: :object } },
                   }
                 },
                  policies: {
                    type: :array,
                    items: {
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
                  },
                }
        run_test!
      end
    end
  end

  # ===========================================================================
  # FOLDER POLICIES — GET /api/v1/folders/{id}/policies
  # ===========================================================================
  path '/api/v1/folders/{id}/policies' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Folder UUID'

    get 'Retrieve explicit and inherited access-control policies for a folder' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns two arrays: `explicit_policies` (rules set directly on this folder)
        and `inherited_policies` (rules propagated from ancestor folders).
        Inherited policies include `source_folder_name` and `source_folder_id`.
      DESC

      response '200', 'Policies returned' do
        let(:id) { FactoryBot.create(:folder, user: admin_user).id }
        schema type: :object,
               properties: {
                 explicit_policies:  {
                   type: :array, items: { '$ref' => '#/components/schemas/FolderPolicy' }
                 },
                 inherited_policies: {
                   type: :array, items: { '$ref' => '#/components/schemas/FolderPolicy' }
                 },
               }
        run_test!
      end

      response '404', 'Folder not found' do
        let(:id) { 'non-existent-uuid' }
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    post 'Upsert an access-control policy for a group on a folder' do
      tags 'Folders'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates or updates the permission matrix for a user group on this folder.
        Pass `cascade: true` to enqueue background propagation to all child folders.
        Requires the calling user to have `manage_access` on the folder (or be an admin).
      DESC

      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[group_id],
        properties: {
          group_id:         { type: :integer, description: 'UserGroup ID' },
          read_access:      { type: :boolean },
          modify_access:    { type: :boolean },
          create_access:    { type: :boolean },
          delete_access:    { type: :boolean },
          replicate_access: { type: :boolean },
          manage_access:    { type: :boolean },
          explicit_deny:    { type: :boolean },
          cascade:          { type: :boolean, description: 'When true, propagate to all child folders in the background' },
        },
      }

      response '200', 'Policy saved' do
        let(:id)   { FactoryBot.create(:folder, user: admin_user).id }
        let(:body) { { group_id: FactoryBot.create(:user_group).id, read_access: true } }
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 policy:  { '$ref' => '#/components/schemas/FolderPolicy' },
               }
        run_test!
      end

      response '403', 'Insufficient permission' do
        let(:id)   { FactoryBot.create(:folder, user: admin_user).id }
        let(:body) { { group_id: 999 } }
        run_test!
      end

      response '404', 'Folder or group not found' do
        let(:id)   { 'non-existent-uuid' }
        let(:body) { { group_id: 1 } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # FOLDER POLICY DELETE — DELETE /api/v1/folders/{id}/policies/{group_id}
  # ===========================================================================
  path '/api/v1/folders/{id}/policies/{group_id}' do
    parameter name: :id,       in: :path,  type: :string,  required: true, description: 'Folder UUID'
    parameter name: :group_id, in: :path,  type: :integer, required: true, description: 'UserGroup ID'
    parameter name: :cascade,  in: :query, type: :boolean, required: false,
                               description: 'When true, remove the policy from all child folders too'

    delete 'Remove an explicit access-control policy from a folder' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'Policy removed' do
        let(:id)       { FactoryBot.create(:folder, user: admin_user).id }
        let(:group_id) { 999 } # no policy → graceful 404
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string },
               }
        run_test!
      end

      response '404', 'Folder or policy not found' do
        let(:id)       { 'non-existent-uuid' }
        let(:group_id) { 1 }
        run_test!
      end
    end
  end
  path '/api/v1/folders/{id}/restore' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Folder ID'

    post 'Restore a soft-deleted folder from the Recycle Bin' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'Folder restored to active state' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Folder restored' },
               }
        run_test!
      end

      response '404', 'Folder not found in the bin' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ===========================================================================
  # PERMANENT DELETE — DELETE /api/v1/folders/{id}/permanent
  # ===========================================================================
  path '/api/v1/folders/{id}/permanent' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Folder ID'

    delete 'Permanently delete a folder from the Recycle Bin' do
      tags 'Folders'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        **Irreversible.** Destroys the folder database record. Also dispatches a
        CDN invalidation job to drop any cached assets under this folder from
        edge nodes. Assets inside the folder should be permanently deleted
        separately (or handled by `dependent: :destroy` on the model association).
      DESC

      response '200', 'Folder permanently deleted' do
        schema type: :object,
               properties: {
                 success: { type: :boolean, example: true },
                 message: { type: :string, example: 'Folder permanently deleted' },
               }
        run_test!
      end

      response '404', 'Folder not found in the bin' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
