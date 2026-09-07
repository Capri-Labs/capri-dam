# An endpoint that wants to be told when review activity happens.
#
# WHY NOT REUSE THE WORKFLOW WEBHOOK
# ----------------------------------
# The workflow engine can already call a URL, but only as a configured *step*
# inside an approval chain. That models "when this workflow reaches this
# point", not "whenever anyone comments". A proofing vendor or project tracker
# wants the latter, and wiring it into a workflow it has no part in would be a
# misuse of the workflow.
#
# SCOPING IS PART OF THE DESIGN
# -----------------------------
# An unscoped subscription receives every comment in the estate, which for a
# large tenant is a firehose that will get the endpoint rate-limited or simply
# ignored. {#asset_id} and {#folder_id} let an integration ask only for the
# work it is actually involved in.
class CommentWebhookSubscription < ApplicationRecord
  # Deliberately small and behavioural. These are the moments an external
  # system can act on: new feedback arrived, or a piece of feedback stopped
  # being outstanding.
  EVENTS = %w[
    comment.created
    comment.resolved
    thread.created
    thread.resolved
    thread.reopened
  ].freeze

  # Beyond this a subscription is treated as broken and skipped, so one dead
  # endpoint cannot keep consuming worker capacity indefinitely.
  FAILURE_LIMIT = 20

  belongs_to :created_by, class_name: "User", optional: true

  validates :name, presence: true
  validates :url, presence: true, format: { with: %r{\Ahttps?://}i, message: "must be an http(s) URL" }
  validates :secret, presence: true
  validate  :events_are_known

  before_validation :generate_secret, on: :create

  scope :enabled, -> { where(active: true).where("consecutive_failures < ?", FAILURE_LIMIT) }

  # Subscriptions that should receive the given event for the given asset.
  #
  # @param event [String] one of {EVENTS}
  # @param asset [Asset]
  # @return [ActiveRecord::Relation]
  scope :listening_for, ->(event, asset) {
    enabled
      .where("asset_id IS NULL OR asset_id = ?", asset.id)
      .where("folder_id IS NULL OR folder_id = ?", asset.folder_id)
      # An empty events list means "everything" — the useful default for a
      # general-purpose integration, and it keeps the common case out of the
      # JSON containment operator.
      .where("jsonb_array_length(events) = 0 OR events @> ?", [ event ].to_json)
  }

  # @param event [String]
  # @return [Boolean]
  def wants?(event)
    events.blank? || events.include?(event)
  end

  # HMAC-SHA256 over the exact bytes sent, which is what lets a receiver verify
  # the payload was not altered in transit and really came from this instance.
  #
  # @param payload [String] the serialised request body
  # @return [String]
  def signature_for(payload)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, payload)}"
  end

  # @param status [Integer]
  def record_success!(status)
    update_columns(
      last_delivered_at: Time.current,
      last_status: status,
      last_error: nil,
      consecutive_failures: 0,
      updated_at: Time.current,
    )
  end

  # @param status [Integer, nil]
  # @param error [String, nil]
  def record_failure!(status: nil, error: nil)
    update_columns(
      last_delivered_at: Time.current,
      last_status: status,
      last_error: error.to_s.truncate(1_000),
      consecutive_failures: consecutive_failures + 1,
      updated_at: Time.current,
    )
  end

  private

  def generate_secret
    self.secret = SecureRandom.hex(32) if secret.blank?
  end

  def events_are_known
    unknown = Array(events) - EVENTS
    return if unknown.empty?

    errors.add(:events, "contains unknown events: #{unknown.join(", ")}")
  end
end
