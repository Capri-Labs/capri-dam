# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::CommentThreads', type: :request do
  annotation_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      comment_id: { type: :string, format: :uuid },
      thread_id: { type: :string, format: :uuid, description: 'Owning thread id for overlay-to-thread navigation' },
      media_type: { type: :string },
      shape: { type: :string },
      bbox: { type: :object },
    },
  }

  comment_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      comment_thread_id: { type: :string, format: :uuid },
      annotations: { type: :array, items: annotation_schema },
    },
  }

  thread_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      asset_id: { type: :string, format: :uuid },
      status: { type: :string, enum: %w[open addressed verified resolved] },
      visibility: { type: :string, enum: %w[internal guest] },
      closed: { type: :boolean },
      origin_version: { type: :object, nullable: true },
      created_by: { type: :object },
      resolved_at: { type: :string, format: 'date-time', nullable: true },
      resolved_by: { type: :object, nullable: true },
      comment_count: { type: :integer },
      comments: { type: :array, items: comment_schema },
      created_at: { type: :string, format: 'date-time' },
      updated_at: { type: :string, format: 'date-time' },
    },
  }

  path '/api/v1/assets/{asset_id}/comments' do
    get 'List review comment threads for an asset' do
      tags 'Comment Threads'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Lists active comment threads attached to an asset. Threads are deliberately
        version-independent so a conversation survives new uploads, while each
        comment inside the thread remains bound to the asset version it was made
        against. Filtering by `version_id` therefore means "threads discussed on
        this version", not "threads owned by this version".

        Geometry filters operate on normalized annotation coordinates in the
        `0..1` media space. Commenting and listing require only `:read` access to
        the asset folder so reviewers without edit rights can participate.
      DESC

      parameter name: :asset_id, in: :path, type: :string, description: 'Asset UUID or id'
      parameter name: :version_id, in: :query, type: :string, required: false
      parameter name: :status, in: :query, type: :string, required: false, enum: %w[open addressed verified resolved]
      parameter name: :unresolved, in: :query, type: :boolean, required: false
      parameter name: :annotated, in: :query, type: :boolean, required: false

      response '200', 'threads listed' do
        schema type: :object,
               properties: {
                 threads: { type: :array, items: thread_schema },
                 meta: {
                   type: :object,
                   properties: {
                     total: { type: :integer },
                     unresolved: { type: :integer },
                   },
                 },
               }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end
    end

    post 'Create a thread with its first comment' do
      tags 'Comment Threads'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Opens a version-independent asset thread and creates the first,
        version-bound comment in one transaction. If `asset_version_id` is
        omitted, the comment is written against the asset's active version.

        Optional annotations use normalized `bbox` coordinates (`x`, `y`, `w`,
        `h`) in the `0..1` source-media space, never pixels, so regions remain
        stable across responsive layouts and renditions. Creating comments only
        requires `:read` access; reviewers are expected to comment without asset
        `:modify` permission.
      DESC

      parameter name: :asset_id, in: :path, type: :string, description: 'Asset UUID or id'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'body' ],
        properties: {
          body: { type: :string, example: 'The logo is clipped in the hero crop.' },
          asset_version_id: { type: :string, format: :uuid, nullable: true },
          visibility: { type: :string, enum: %w[internal guest], example: 'internal' },
          motivation: { type: :string, example: 'editing' },
          annotations: {
            type: :array,
            items: {
              type: :object,
              properties: {
                media_type: { type: :string, enum: %w[image video document] },
                shape: { type: :string, enum: %w[pin rect ellipse arrow line freehand text highlight] },
                bbox: {
                  type: :object,
                  properties: {
                    x: { type: :number, example: 0.1 },
                    y: { type: :number, example: 0.2 },
                    w: { type: :number, example: 0.3 },
                    h: { type: :number, example: 0.1 },
                  },
                },
                source: { type: :object, example: { width: 4000, height: 3000 } },
              },
            },
          },
        },
      }

      response '201', 'thread created' do
        schema thread_schema
        run_test!
      end

      response '422', 'invalid or missing body/annotation payload' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/comment_threads/{id}' do
    get 'Fetch one comment thread' do
      tags 'Comment Threads'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns a deep-linkable thread representation with active root comments,
        single-level replies and normalized annotations. The thread address is
        standalone because notifications and mention emails point directly to the
        conversation, while access is still checked through the thread's asset.
      DESC
      parameter name: :id, in: :path, type: :string, format: :uuid

      response '200', 'thread found' do
        schema thread_schema
        run_test!
      end

      response '404', 'thread not found' do
        run_test!
      end
    end

    patch 'Update a thread visibility flag' do
      tags 'Comment Threads'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Updates direct thread metadata only. Lifecycle status changes use the
        dedicated resolve/reopen endpoints so resolution attribution is always
        captured. Owners may manage their own thread; non-owners need asset
        folder `:modify` permission.
      DESC
      parameter name: :id, in: :path, type: :string, format: :uuid
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'visibility' ],
        properties: { visibility: { type: :string, enum: %w[internal guest] } },
      }

      response '200', 'visibility updated' do
        schema thread_schema
        run_test!
      end

      response '403', 'not allowed to manage this thread' do
        run_test!
      end

      response '422', 'visibility missing or invalid' do
        run_test!
      end
    end

    delete 'Soft-delete a comment thread' do
      tags 'Comment Threads'
      security [ Bearer: [] ]
      description <<~DESC
        Soft-deletes the thread so review history remains auditable while active
        indexes no longer return it. Deleting someone else's thread is a
        moderation action and requires asset folder `:modify`; the thread owner
        may delete their own thread with only read access.
      DESC
      parameter name: :id, in: :path, type: :string, format: :uuid

      response '204', 'thread soft-deleted' do
        run_test!
      end

      response '403', 'not allowed to delete this thread' do
        run_test!
      end
    end
  end

  path '/api/v1/comment_threads/{id}/resolve' do
    patch 'Resolve or verify a thread' do
      tags 'Comment Threads'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Closes a thread as `resolved` or `verified`. `verified` means the
        original reviewer confirmed the fix, while `resolved` closes without
        further action. Resolution stamps `resolved_at` and `resolved_by`; only
        owners or users with folder `:modify` can resolve someone else's thread.
      DESC
      parameter name: :id, in: :path, type: :string, format: :uuid
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { status: { type: :string, enum: %w[resolved verified], default: 'resolved' } },
      }

      response '200', 'thread closed' do
        schema thread_schema
        run_test!
      end

      response '422', 'unsupported resolve status' do
        run_test!
      end
    end
  end

  path '/api/v1/comment_threads/{id}/reopen' do
    patch 'Reopen a closed thread' do
      tags 'Comment Threads'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Moves a closed thread back to `open` and clears resolution attribution.
        The thread remains version-independent; subsequent comments continue to
        record whichever asset version they discuss.
      DESC
      parameter name: :id, in: :path, type: :string, format: :uuid

      response '200', 'thread reopened' do
        schema thread_schema
        run_test!
      end

      response '403', 'not allowed to reopen this thread' do
        run_test!
      end
    end
  end
end
