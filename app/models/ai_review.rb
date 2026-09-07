# One run of the AI review assistant against one version of one asset.
#
# WHY THE RUN IS RECORDED SEPARATELY FROM ITS FINDINGS
# ----------------------------------------------------
# Without a run row, "the assistant looked and found nothing" and "the
# assistant never looked" are the same empty list. That distinction is the
# whole value of an automated check: a reviewer needs to know whether silence
# means clean or means unexamined.
#
# The run also pins +ai_model_name+ and +provider+ at execution time rather than
# resolving them later through {AiModelConfig}. Model configuration changes,
# and a finding must stay attributable to the thing that actually produced it —
# otherwise last month's suggestion appears to have come from this month's
# model.
#
# INFERENCE HAPPENS OUTSIDE RAILS
# -------------------------------
# Like every other AI feature here, the actual vision call is performed by the
# external AI gateway. Rails publishes a dispatch event and the gateway posts
# findings back to {Api::V1::AiReviewsController#findings}. This class is the
# state machine and audit record for that round trip, not an inference client.
class AiReview < ApplicationRecord
  STATUSES = %w[queued running completed failed cancelled].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze

  # A profile is the question being asked of the model. Keeping it an explicit
  # allow-list rather than a free-text prompt means a caller cannot use this
  # endpoint to run arbitrary instructions against a customer's assets.
  PROFILES = {
    "brand_guidelines" => "Brand guideline breaches: off-brand colour, wrong logo, misused type.",
    "accessibility" => "Legibility and contrast problems that would fail WCAG.",
    "safe_area" => "Logo and text falling outside the safe area, or too close to the edge.",
    "composition" => "Cropping, framing and focal-point problems.",
  }.freeze

  belongs_to :asset
  belongs_to :asset_version, optional: true
  belongs_to :requested_by, class_name: "User", optional: true

  # Findings are threads. Destroying a run destroys the suggestions it made,
  # which is correct while they are pending — but see {#destroyable?}: a run
  # whose findings were accepted has become part of the human review record.
  has_many :comment_threads, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :profile, inclusion: { in: PROFILES.keys }
  validates :findings_count, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_asset, ->(asset) { where(asset: asset) }
  scope :in_flight, -> { where(status: %w[queued running]) }

  # @return [Boolean] whether the run has finished, successfully or not
  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # A run that produced accepted findings is no longer purely machine output —
  # a human has folded it into the review. Deleting it would silently remove
  # the provenance of comments the team is now acting on.
  #
  # @return [Boolean]
  def destroyable?
    comment_threads.where(suggestion_state: "accepted").none?
  end

  # @return [String] human-readable description of what was checked
  def profile_label
    PROFILES.fetch(profile, profile)
  end

  def start!
    update!(status: "running", started_at: Time.current)
  end

  # @param count [Integer] number of findings imported
  def complete!(count)
    update!(
      status: "completed",
      findings_count: count,
      completed_at: Time.current,
    )
  end

  # @param message [String] why the run failed
  def fail!(message)
    update!(
      status: "failed",
      error_message: message.to_s.truncate(1_000),
      completed_at: Time.current,
    )
  end

  # Payload published to the AI gateway. Mirrors {AiBatchJob#to_gateway_payload}
  # so the gateway sees one consistent event shape.
  #
  # Deliberately carries no storage credentials: the gateway fetches the media
  # through a callback URL we control, so revoking the run revokes its access.
  #
  # @return [Hash]
  def to_gateway_payload
    {
      event: "ai_review.dispatch",
      review_id: id,
      asset_id: asset_id,
      asset_version_id: asset_version_id,
      profile: profile,
      instruction: profile_label,
      capability: "vision",
      options: options,
      callback_url: Rails.application.routes.url_helpers
                         .findings_api_v1_ai_review_url(self, host: callback_host),
    }
  end

  private

  def callback_host
    Rails.application.credentials.dig(:app, :host).presence ||
      ENV.fetch("APP_HOST", "http://localhost:3000")
  end
end
