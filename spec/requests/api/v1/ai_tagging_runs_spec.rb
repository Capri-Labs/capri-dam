# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::AiTaggingRuns', type: :request do
  run_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      asset_id: { type: :string, format: :uuid },
      status: { type: :string, enum: %w[queued running completed failed] },
      profile: { type: :string, enum: %w[general_subject product scene_mood] },
      trigger: { type: :string, enum: %w[upload manual batch] },
      model_name: { type: :string, nullable: true },
      provider: { type: :string, nullable: true },
      suggestions_count: { type: :integer },
      error_message: { type: :string, nullable: true },
      requested_by: { type: :string, nullable: true, description: 'Null for an automatic upload-time run' },
      started_at: { type: :string, format: 'date-time', nullable: true },
      completed_at: { type: :string, format: 'date-time', nullable: true },
      created_at: { type: :string, format: 'date-time' },
    },
  }

  suggestion_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      asset_id: { type: :string, format: :uuid },
      run_id: { type: :string, format: :uuid },
      label: { type: :string, example: 'sunset' },
      confidence: { type: :number, nullable: true, description: '0..1, or null if the model did not report one' },
      state: { type: :string, enum: %w[pending accepted dismissed] },
      decided_by: { type: :string, nullable: true },
      decided_at: { type: :string, format: 'date-time', nullable: true },
      created_at: { type: :string, format: 'date-time' },
    },
  }

  path '/api/v1/assets/{asset_id}/ai_tagging_runs' do
    parameter name: :asset_id, in: :path, type: :string, required: true,
              description: 'Asset database ID or UUID'

    get "List an asset's tagging runs" do
      tags 'AI Tagging'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Each run is one dispatch of this asset to a vision model.

        The run exists so the pipeline is safe to retry: dispatch is a no-op
        unless the run is still `queued`, and a failure is *visible* rather than
        indistinguishable from a model that simply found nothing to say.

        Requires `read` on the asset.
      DESC

      response '200', 'runs listed' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset_id) { FactoryBot.create(:asset, user: user).id }

        schema type: :object, properties: { runs: { type: :array, items: run_schema } }
        run_test!
      end
    end

    post 'Request tag suggestions for an asset' do
      tags 'AI Tagging'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Queues a vision model to propose subject tags.

        **Nothing is applied automatically.** Labels come back as *pending
        suggestions* that a person accepts or dismisses. Tags are load-bearing —
        people search on them, collections filter on them, rights rules can key
        off them — so a library whose vocabulary silently blends curated and
        speculative terms cannot be trusted, and there is no cheap way to
        separate them again afterwards.

        `profile` is an **allow-listed key, never a prompt**: `general_subject`,
        `product`, `scene_mood`. An unrecognised value falls back to
        `general_subject` rather than being passed through, because a caller
        able to dictate the instruction could redirect the model to do something
        other than tagging under our credentials.

        Returns `409` if a run is already in flight for this asset — a second
        one would propose the same labels twice and double the triage burden for
        no new information.

        Requires `modify` on the asset.
      DESC

      parameter name: :payload, in: :body, required: false, schema: {
        type: :object,
        properties: {
          profile: { type: :string, enum: %w[general_subject product scene_mood] },
        },
      }

      response '201', 'run queued' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset_id) { FactoryBot.create(:asset, user: user).id }
        let(:payload) { { profile: 'general_subject' } }

        schema run_schema
        run_test!
      end

      response '409', 'a run is already in flight' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset) { FactoryBot.create(:asset, user: user) }
        let(:asset_id) { asset.id }
        let(:payload) { {} }

        before { FactoryBot.create(:ai_tagging_run, asset: asset, status: 'running') }

        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/assets/{asset_id}/ai_tag_suggestions' do
    parameter name: :asset_id, in: :path, type: :string, required: true

    get 'List the pending suggestion queue for an asset' do
      tags 'AI Tagging'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        What the machine proposes for this asset that nobody has ruled on yet,
        highest confidence first.

        Already-decided suggestions are excluded. Dismissed rows are retained
        rather than deleted so the same label is not proposed and rejected
        forever, but they do not reappear in the queue.

        Requires `read` on the asset.
      DESC

      response '200', 'pending suggestions listed' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset_id) { FactoryBot.create(:asset, user: user).id }

        schema type: :object,
               properties: { suggestions: { type: :array, items: suggestion_schema } }
        run_test!
      end
    end
  end

  path '/api/v1/ai_tagging_runs/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Run UUID'

    get 'Show one tagging run and its suggestions' do
      tags 'AI Tagging'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Addressable in its own right so a client can poll a queued run to completion.'

      response '200', 'run returned' do
        let(:user) { FactoryBot.create(:user) }
        let(:id) { FactoryBot.create(:ai_tagging_run, asset: FactoryBot.create(:asset, user: user)).id }

        schema run_schema
        run_test!
      end

      response '404', 'run not found' do
        let(:id) { '00000000-0000-0000-0000-000000000000' }
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/ai_tagging_runs/{id}/suggestions' do
    parameter name: :id, in: :path, type: :string, required: true

    post 'AI Gateway callback: deliver proposed labels' do
      tags 'AI Tagging'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        Called by the AI Gateway, **not** by an API client. Authenticated with
        the shared `X-Gateway-Secret` header rather than a user session, because
        the gateway is a machine caller with no account.

        This endpoint can only ever create *pending* rows. It has no path to the
        asset's real tags — that promotion happens exclusively through
        `/accept`, under a signed-in user with `modify` rights.

        The payload is treated as untrusted input. Labels are normalised and
        length-checked, confidence is clamped into `0..1`, the list is capped,
        and a malformed entry is skipped rather than aborting the import — one
        bad label should not discard nine good ones.

        Three classes of label are discarded outright: those below the
        confidence floor, those the asset already carries, and those a person
        dismissed on a previous run.

        Posting `{ "error": "..." }` instead marks the run failed, so a gateway
        outage is visible rather than looking like a model that found nothing.

        Returns `409` for a run that has already terminated, so a replayed or
        late delivery cannot duplicate every label.
      DESC

      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        properties: {
          suggestions: {
            type: :array,
            items: {
              type: :object,
              properties: {
                label: { type: :string, example: 'sunset' },
                confidence: { type: :number, example: 0.91 },
              },
            },
          },
          error: { type: :string, description: 'Present instead of suggestions when the run failed' },
        },
      }

      response '401', 'missing or wrong gateway secret' do
        let(:id) { FactoryBot.create(:ai_tagging_run, status: 'running').id }
        let(:payload) { { suggestions: [] } }

        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/ai_tag_suggestions/{id}/accept' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Suggestion UUID'

    post 'Accept a proposed tag' do
      tags 'AI Tagging'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        The **only** path in the system that writes a machine-derived label into
        `assets.properties["tags"]`.

        Idempotent in effect: a label the asset already carries is not added
        twice, and a suggestion that has already been decided returns `409` so
        two curators clicking at once cannot double-apply it.

        Requires `modify` on the asset — promoting a machine guess into the
        library's vocabulary is not a read-adjacent act.
      DESC

      response '200', 'accepted and applied to the asset' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset) { FactoryBot.create(:asset, user: user) }
        let(:id) do
          FactoryBot.create(:ai_tag_suggestion,
                            ai_tagging_run: FactoryBot.create(:ai_tagging_run, asset: asset),
                            asset: asset).id
        end

        schema suggestion_schema
        run_test!
      end
    end
  end

  path '/api/v1/ai_tag_suggestions/{id}/dismiss' do
    parameter name: :id, in: :path, type: :string, required: true

    post 'Dismiss a proposed tag' do
      tags 'AI Tagging'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Rejects the machine's guess. The row is **kept**, not deleted: a
        rejection is a decision, and discarding it would let the next run
        propose the same label to be rejected again, forever.

        Deliberately does *not* remove the label from the asset's tags. If a
        person had separately applied that tag themselves, that is their
        decision and it stands.

        Requires `modify` on the asset.
      DESC

      response '200', 'dismissed' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset) { FactoryBot.create(:asset, user: user) }
        let(:id) do
          FactoryBot.create(:ai_tag_suggestion,
                            ai_tagging_run: FactoryBot.create(:ai_tagging_run, asset: asset),
                            asset: asset).id
        end

        schema suggestion_schema
        run_test!
      end
    end
  end
end
