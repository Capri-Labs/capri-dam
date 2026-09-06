# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Comments', type: :request do
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
      parent_comment_id: { type: :string, format: :uuid, nullable: true },
      body: { type: :string },
      motivation: { type: :string },
      agent_type: { type: :string, enum: %w[person software] },
      agent_name: { type: :string, nullable: true },
      confidence: { type: :number, nullable: true },
      author: { type: :object, nullable: true },
      author_display_name: { type: :string },
      asset_version: { type: :object, nullable: true },
      edited: { type: :boolean },
      edited_at: { type: :string, format: 'date-time', nullable: true },
      annotations: { type: :array, items: annotation_schema },
      replies: { type: :array, items: { type: :object } },
      created_at: { type: :string, format: 'date-time' },
    },
  }

  path '/api/v1/comment_threads/{comment_thread_id}/comments' do
    post 'Reply to or add a follow-up comment in a thread' do
      tags 'Comments'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Adds a version-bound comment to an existing, version-independent asset
        thread. Supplying `parent_comment_id` creates a single-level reply; the
        model rejects replies to replies so review sidebars stay flat.

        `asset_version_id` defaults to the asset's active version. Optional
        annotations use normalized `0..1` geometry and may include frame-native
        video positions. Posting a comment requires only `:read` access; setting
        `mark_addressed` explicitly moves still-open feedback to `addressed`.
      DESC

      parameter name: :comment_thread_id, in: :path, type: :string, format: :uuid
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'body' ],
        properties: {
          body: { type: :string, example: 'Fixed in the new version.' },
          parent_comment_id: { type: :string, format: :uuid, nullable: true },
          asset_version_id: { type: :string, format: :uuid, nullable: true },
          motivation: { type: :string, example: 'replying' },
          mark_addressed: { type: :boolean, example: true },
          annotations: { type: :array, items: annotation_schema },
        },
      }

      response '201', 'comment created' do
        schema comment_schema
        run_test!
      end

      response '404', 'parent comment not found in this thread' do
        run_test!
      end

      response '422', 'invalid or missing body' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/comments/{id}' do
    patch 'Edit a comment body' do
      tags 'Comments'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Edits a comment body and stamps `edited_at`, letting clients display an
        explicit edited state instead of rewriting review history invisibly. Only
        the original author may edit; asset managers cannot rewrite another
        participant's words.
      DESC
      parameter name: :id, in: :path, type: :string, format: :uuid
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'body' ],
        properties: { body: { type: :string, example: 'Updated wording.' } },
      }

      response '200', 'comment edited' do
        schema comment_schema
        run_test!
      end

      response '403', 'not the comment author' do
        run_test!
      end

      response '422', 'body missing or invalid' do
        run_test!
      end
    end

    delete 'Soft-delete a comment' do
      tags 'Comments'
      security [ Bearer: [] ]
      description <<~DESC
        Soft-deletes a comment for auditability. The row remains in storage, but
        active serializers and thread indexes omit it. Only the author may delete
        their own comment.
      DESC
      parameter name: :id, in: :path, type: :string, format: :uuid

      response '204', 'comment soft-deleted' do
        run_test!
      end

      response '403', 'not the comment author' do
        run_test!
      end
    end
  end
end
