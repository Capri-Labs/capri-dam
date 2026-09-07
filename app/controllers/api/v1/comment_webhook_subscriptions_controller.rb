# CRUD for outbound review-activity webhooks.
#
# ADMIN-ONLY, DELIBERATELY
# ------------------------
# A subscription is an instruction to send internal review conversation to an
# arbitrary external URL. That is a data-egress decision, not a per-asset
# permission, so it sits with administrators rather than with anyone who
# happens to hold +:modify+ on a folder.
class Api::V1::CommentWebhookSubscriptionsController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!
  before_action :set_subscription, only: %i[show update destroy test]

  # GET /api/v1/comment_webhook_subscriptions
  def index
    subscriptions = CommentWebhookSubscription.order(created_at: :desc)
    render json: {
      events: CommentWebhookSubscription::EVENTS,
      subscriptions: subscriptions.map { |s| serialize(s) },
    }
  end

  # GET /api/v1/comment_webhook_subscriptions/:id
  def show
    render json: serialize(@subscription)
  end

  # POST /api/v1/comment_webhook_subscriptions
  def create
    subscription = CommentWebhookSubscription.new(subscription_params)
    subscription.created_by = current_user

    if subscription.save
      # The secret is returned exactly once, on creation, because the receiver
      # needs it to verify signatures and there is no way to recover it later
      # without weakening the record.
      render json: serialize(subscription).merge(secret: subscription.secret), status: :created
    else
      render json: { errors: subscription.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/comment_webhook_subscriptions/:id
  def update
    if @subscription.update(subscription_params)
      # Editing a subscription is the natural moment to give a previously
      # failing endpoint another chance.
      @subscription.update_columns(consecutive_failures: 0) if @subscription.consecutive_failures.positive?
      render json: serialize(@subscription.reload)
    else
      render json: { errors: @subscription.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/comment_webhook_subscriptions/:id
  def destroy
    @subscription.destroy
    head :no_content
  end

  # POST /api/v1/comment_webhook_subscriptions/:id/test
  #
  # Sends a synthetic ping so an integrator can confirm reachability and
  # signature verification before real review activity depends on it.
  def test
    body = {
      event: "ping",
      delivered_at: Time.current.iso8601,
      subscription: { id: @subscription.id, name: @subscription.name },
    }.to_json

    response = Faraday.new { |f| f.options.timeout = CommentWebhookWorker::TIMEOUT }.post(@subscription.url) do |req|
      req.headers["Content-Type"]      = "application/json"
      req.headers["X-Capri-Event"]     = "ping"
      req.headers["X-Capri-Signature"] = @subscription.signature_for(body)
      req.body = body
    end

    render json: { ok: response.success?, status: response.status, body: response.body.to_s.truncate(500) }
  rescue Faraday::Error => e
    # A failed ping is a successful test — it told the integrator what is
    # wrong. Reporting it as a 5xx would suggest Capri is broken.
    render json: { ok: false, status: nil, error: e.message }
  end

  private

  def set_subscription
    @subscription = CommentWebhookSubscription.find(params[:id])
  end

  def subscription_params
    params.require(:comment_webhook_subscription)
          .permit(:name, :url, :active, :asset_id, :folder_id, events: [])
  end

  # The secret is never included: once stored it is write-only, so a leaked
  # admin session cannot be used to harvest signing keys for endpoints it did
  # not create.
  def serialize(subscription)
    {
      id: subscription.id,
      name: subscription.name,
      url: subscription.url,
      events: subscription.events,
      active: subscription.active,
      asset_id: subscription.asset_id,
      folder_id: subscription.folder_id,
      created_by: subscription.created_by && {
        id: subscription.created_by.id,
        email: subscription.created_by.email,
      },
      health: {
        last_delivered_at: subscription.last_delivered_at,
        last_status: subscription.last_status,
        last_error: subscription.last_error,
        consecutive_failures: subscription.consecutive_failures,
        # Surfaced explicitly so an operator can see *why* an "active"
        # subscription has gone quiet.
        suspended: subscription.consecutive_failures >= CommentWebhookSubscription::FAILURE_LIMIT,
      },
      created_at: subscription.created_at,
      updated_at: subscription.updated_at,
    }
  end
end
