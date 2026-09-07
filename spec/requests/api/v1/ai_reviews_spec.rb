# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::AiReviews', type: :request do
  review_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      asset_id: { type: :string, format: :uuid },
      asset_version_id: { type: :string, format: :uuid, nullable: true },
      status: { type: :string, enum: AiReview::STATUSES },
      profile: { type: :string, enum: AiReview::PROFILES.keys },
      profile_label: { type: :string, description: 'What the assistant was asked to check' },
      model_name: { type: :string, nullable: true, example: 'gpt-4o' },
      provider: { type: :string, nullable: true, example: 'openai' },
      findings_count: { type: :integer },
      error_message: { type: :string, nullable: true },
      requested_by: { type: :string, nullable: true },
      started_at: { type: :string, format: 'date-time', nullable: true },
      completed_at: { type: :string, format: 'date-time', nullable: true },
      created_at: { type: :string, format: 'date-time' },
    },
  }

  path '/api/v1/assets/{asset_id}/ai_reviews' do
    parameter name: :asset_id, in: :path, type: :string, format: :uuid

    get 'List AI review runs for an asset' do
      tags 'AI Reviews'
      produces 'application/json'
      security [ bearer_auth: [] ]

      response '200', 'runs listed' do
        schema type: :object,
               properties: { reviews: { type: :array, items: review_schema } }
        run_test!
      end
    end

    post 'Request an AI review of an asset' do
      tags 'AI Reviews'
      description <<~DESC
        Runs a vision model over the asset and posts its findings as real
        annotated comment threads, each marked `suggestion_state: "pending"`
        until a human accepts or dismisses it.

        Requires `:modify` on the asset rather than the `:read` that ordinary
        commenting needs: a run discloses the asset to an external inference
        service and spends against the AI budget.

        `profile` is an allow-list, not a free-text prompt, so this endpoint
        cannot be used to run arbitrary instructions against stored assets.
      DESC
      tags 'AI Reviews'
      consumes 'application/json'
      produces 'application/json'
      security [ bearer_auth: [] ]

      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          profile: { type: :string, enum: AiReview::PROFILES.keys, default: 'brand_guidelines' },
          options: {
            type: :object,
            description: 'Bounded knobs forwarded to the gateway',
            properties: {
              brand_kit_id: { type: :string },
              locale: { type: :string },
              strictness: { type: :string },
            },
          },
        },
      }

      response '201', 'review queued' do
        schema type: :object, properties: { review: review_schema }
        run_test!
      end

      response '409', 'a review is already running for this asset' do
        run_test!
      end

      response '422', 'unknown profile' do
        run_test!
      end
    end
  end

  path '/api/v1/assets/{asset_id}/ai_reviews/pending' do
    parameter name: :asset_id, in: :path, type: :string, format: :uuid

    get 'Triage queue: suggestions awaiting a human decision' do
      tags 'AI Reviews'
      description <<~DESC
        Threads the assistant opened that nobody has ruled on yet. These are
        deliberately absent from `GET /api/v1/assets/{id}/comments`, from
        exports, and from the guest review surface — machine output is not part
        of the review until a person accepts it.
      DESC
      produces 'application/json'
      security [ bearer_auth: [] ]

      response '200', 'pending suggestions listed' do
        run_test!
      end
    end
  end

  path '/api/v1/ai_reviews/{id}' do
    parameter name: :id, in: :path, type: :string, format: :uuid

    get 'Fetch a single review run' do
      tags 'AI Reviews'
      produces 'application/json'
      security [ bearer_auth: [] ]

      response '200', 'run returned' do
        schema type: :object, properties: { review: review_schema }
        run_test!
      end

      response '404', 'no such run' do
        run_test!
      end
    end
  end

  path '/api/v1/ai_reviews/{id}/findings' do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post 'Gateway callback: deliver findings for a run' do
      tags 'AI Reviews'
      description <<~DESC
        Called by the AI gateway, not by a user. Authenticated with the shared
        `X-Gateway-Secret` header rather than a user session or bearer token.

        The payload is treated as untrusted: coordinates are clamped into the
        unit square, bodies are length-capped, low-confidence findings are
        dropped, and a malformed finding is skipped rather than aborting the
        run. A delivery for an already-finished run is ignored, so a retry
        cannot duplicate findings a reviewer has already triaged.
      DESC
      consumes 'application/json'
      produces 'application/json'

      parameter name: 'X-Gateway-Secret', in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          error: { type: :string, description: 'Set instead of findings when the run failed' },
          findings: {
            type: :array,
            items: {
              type: :object,
              properties: {
                title: { type: :string },
                detail: { type: :string },
                rule: { type: :string, description: 'Guideline breached, quoted into the note' },
                confidence: { type: :number, format: :float, minimum: 0, maximum: 1 },
                annotations: {
                  type: :array,
                  items: {
                    type: :object,
                    properties: {
                      shape: { type: :string, enum: AnnotationTarget::SHAPES },
                      bbox: {
                        type: :object,
                        description: 'Normalised 0..1, upper-left origin',
                        properties: {
                          x: { type: :number }, y: { type: :number },
                          w: { type: :number }, h: { type: :number }
                        },
                      },
                      svg_path: { type: :string, description: 'Required for arrow, line and freehand' },
                      label: { type: :string },
                    },
                  },
                },
              },
            },
          },
        },
      }

      response '200', 'findings imported' do
        schema type: :object,
               properties: {
                 status: { type: :string },
                 imported: { type: :integer },
                 skipped: { type: :integer },
                 errors: { type: :array, items: { type: :string } },
               }
        run_test!
      end

      response '401', 'missing or wrong gateway secret' do
        run_test!
      end
    end
  end

  path '/api/v1/comment_threads/{id}/accept_suggestion' do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post 'Accept an AI suggestion into the review' do
      tags 'AI Reviews'
      description <<~DESC
        Admits the suggestion into the human review. The accepting user is
        recorded as the decision-maker, but authorship stays with the machine —
        `agent_type` remains `software`, so the audit trail is not laundered
        into a person's name.
      DESC
      produces 'application/json'
      security [ bearer_auth: [] ]

      response '200', 'accepted' do
        run_test!
      end

      response '422', 'not a pending suggestion' do
        run_test!
      end
    end
  end

  path '/api/v1/comment_threads/{id}/dismiss_suggestion' do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post 'Dismiss an AI suggestion' do
      tags 'AI Reviews'
      description <<~DESC
        Rejects the suggestion. The thread is kept rather than deleted: a
        dismissed false positive is the only evidence available for tuning the
        model, and a deleted one is simply raised again on the next run.
      DESC
      produces 'application/json'
      security [ bearer_auth: [] ]

      response '200', 'dismissed' do
        run_test!
      end
    end
  end
end
