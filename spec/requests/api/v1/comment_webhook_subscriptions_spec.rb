# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::CommentWebhookSubscriptions', type: :request do
  health_schema = {
    type: :object,
    properties: {
      last_delivered_at: { type: :string, format: 'date-time', nullable: true },
      last_status: { type: :integer, nullable: true },
      last_error: { type: :string, nullable: true },
      consecutive_failures: { type: :integer },
      suspended: {
        type: :boolean,
        description: 'True once the failure limit is reached; the subscription stays "active" but stops being delivered to',
      },
    },
  }

  subscription_schema = {
    type: :object,
    properties: {
      id: { type: :integer },
      name: { type: :string, example: 'Proofing vendor' },
      url: { type: :string, example: 'https://vendor.example/hooks/capri' },
      events: {
        type: :array,
        items: { type: :string, enum: CommentWebhookSubscription::EVENTS },
        description: 'An empty array means every event',
      },
      active: { type: :boolean },
      asset_id: { type: :string, format: :uuid, nullable: true },
      folder_id: { type: :string, format: :uuid, nullable: true },
      created_by: { type: :object, nullable: true },
      health: health_schema,
      created_at: { type: :string, format: 'date-time' },
      updated_at: { type: :string, format: 'date-time' },
    },
  }

  write_payload = {
    type: :object,
    required: [ 'comment_webhook_subscription' ],
    properties: {
      comment_webhook_subscription: {
        type: :object,
        properties: {
          name: { type: :string, example: 'Proofing vendor' },
          url: { type: :string, example: 'https://vendor.example/hooks/capri' },
          events: { type: :array, items: { type: :string, enum: CommentWebhookSubscription::EVENTS } },
          active: { type: :boolean },
          asset_id: { type: :string, format: :uuid, nullable: true },
          folder_id: { type: :string, format: :uuid, nullable: true },
        },
      },
    },
  }

  path '/api/v1/comment_webhook_subscriptions' do
    get 'List review-activity webhook subscriptions' do
      tags 'Comment Webhooks'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Lists registered outbound webhooks for review activity, along with the
        set of event names available to subscribe to.

        These are **subscriptions**, as distinct from the workflow engine's
        per-step webhook action. The workflow webhook models "when this
        workflow reaches this point"; a subscription models "whenever anyone
        comments", which is what a proofing vendor or project tracker actually
        wants and which no workflow should have to be invented for.

        The signing secret is never returned here. It is disclosed exactly once,
        at creation, so a hijacked administrator session cannot be used to
        harvest signing keys for endpoints it did not create.

        Administrator only: a subscription sends internal review conversation to
        an arbitrary external URL, which is a data-egress decision rather than a
        per-asset permission.
      DESC

      response '200', 'subscriptions listed' do
        schema type: :object,
               properties: {
                 events: { type: :array, items: { type: :string, enum: CommentWebhookSubscription::EVENTS } },
                 subscriptions: { type: :array, items: subscription_schema },
               }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end

      response '403', 'not an administrator' do
        run_test!
      end
    end

    post 'Register a review-activity webhook' do
      tags 'Comment Webhooks'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates a subscription and returns its signing `secret` **once**. Store
        it: every delivery carries an `X-Capri-Signature` header of
        `sha256=<HMAC-SHA256 of the exact request body>`, and the secret cannot
        be read back afterwards.

        Deliveries also carry `X-Capri-Event` and a unique `X-Capri-Delivery`
        id. Retries reuse the delivery id, so a receiver that has already
        processed it can drop the duplicate.

        Scope the subscription with `asset_id` or `folder_id` unless you really
        want every comment in the estate — an unscoped subscription on a large
        tenant is a firehose. Leave `events` empty to receive everything.

        A subscription that fails #{CommentWebhookSubscription::FAILURE_LIMIT}
        times consecutively stops being delivered to, so one dead endpoint
        cannot consume worker capacity indefinitely. Updating it clears the
        counter.
      DESC

      parameter name: :payload, in: :body, schema: write_payload

      response '201', 'subscription created; secret returned once' do
        schema subscription_schema.deep_merge(
          properties: { secret: { type: :string, description: 'Shown only on creation' } }
        )
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end

      response '403', 'not an administrator' do
        run_test!
      end

      response '422', 'invalid URL or unknown event name' do
        schema type: :object, properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/api/v1/comment_webhook_subscriptions/{id}' do
    parameter name: :id, in: :path, type: :integer

    get 'Fetch one webhook subscription' do
      tags 'Comment Webhooks'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Returns the subscription including its delivery health, so an operator can see why an "active" endpoint has gone quiet.'

      response '200', 'subscription found' do
        schema subscription_schema
        run_test!
      end

      response '404', 'subscription not found' do
        run_test!
      end
    end

    patch 'Update a webhook subscription' do
      tags 'Comment Webhooks'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Updates the endpoint, its event filter or its scope. A successful update
        also resets `consecutive_failures`, since editing a subscription is the
        natural moment to give a previously failing endpoint another chance.
      DESC

      parameter name: :payload, in: :body, schema: write_payload

      response '200', 'subscription updated' do
        schema subscription_schema
        run_test!
      end

      response '422', 'invalid URL or unknown event name' do
        schema type: :object, properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end

    delete 'Remove a webhook subscription' do
      tags 'Comment Webhooks'
      security [ Bearer: [] ]
      description 'Deletes the subscription. In-flight deliveries for it are dropped rather than retried.'

      response '204', 'subscription removed' do
        run_test!
      end

      response '404', 'subscription not found' do
        run_test!
      end
    end
  end

  path '/api/v1/comment_webhook_subscriptions/{id}/test' do
    parameter name: :id, in: :path, type: :integer

    post 'Send a signed test ping' do
      tags 'Comment Webhooks'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Posts a synthetic `ping` event to the configured URL, signed with the
        subscription's secret, so an integrator can confirm reachability and
        verify their signature implementation before real review activity
        depends on it.

        An unreachable endpoint still returns **200** with `ok: false`: a failed
        ping is a successful test — it told the integrator what is wrong — and
        reporting it as a 5xx would wrongly implicate Capri. Test pings do not
        count towards the failure limit.
      DESC

      response '200', 'ping attempted; inspect ok/status/error' do
        schema type: :object,
               properties: {
                 ok: { type: :boolean },
                 status: { type: :integer, nullable: true },
                 body: { type: :string },
                 error: { type: :string, nullable: true },
               }
        run_test!
      end

      response '403', 'not an administrator' do
        run_test!
      end
    end
  end
end
