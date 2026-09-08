# One dispatch of one asset to the AI Gateway's tagging capability.
#
# Mirrors {AiReview} deliberately: same status vocabulary, same start!/complete!/
# fail! lifecycle, same gateway payload shape. The two pipelines answer different
# questions — "what is wrong with this?" versus "what is this of?" — but they
# have identical failure modes, and giving them identical mechanics means a fix
# to one is legible in the other.
#
# @see AiTagSuggestion
# @see AiAutoTagWorker
class AiTaggingRun < ApplicationRecord
  STATUSES          = %w[queued running completed failed].freeze
  TERMINAL_STATUSES = %w[completed failed].freeze
  TRIGGERS          = %w[upload manual batch].freeze

  # Allow-listed capability keys. A client names one of these; it never supplies
  # a prompt. Free text would let a caller redirect the model to do something
  # other than tagging, at our expense and under our credentials.
  PROFILES = {
    "general_subject" => "Identify the subjects, objects and setting visible in the image.",
    "product"         => "Identify product type, material, colour and packaging.",
    "scene_mood"      => "Identify scene, lighting and mood.",
  }.freeze

  # A model that returns forty near-certain labels is useful; one that returns
  # forty guesses at 0.2 is a person's afternoon. The floor discards noise and
  # the cap bounds the triage burden however chatty the model is.
  MIN_CONFIDENCE = 0.55
  MAX_SUGGESTIONS = 25

  belongs_to :asset
  belongs_to :asset_version, optional: true
  belongs_to :requested_by, class_name: "User", optional: true

  has_many :ai_tag_suggestions, dependent: :destroy

  validates :status,  inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :profile, inclusion: { in: PROFILES.keys }

  scope :in_flight, -> { where(status: %w[queued running]) }
  scope :recent,    -> { order(created_at: :desc) }

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def profile_instruction
    PROFILES[profile]
  end

  def start!
    update!(status: "running", started_at: Time.current)
  end

  def complete!(count)
    update!(status: "completed", suggestions_count: count, completed_at: Time.current)
  end

  def fail!(message)
    update!(status: "failed", error_message: message.to_s.truncate(1000), completed_at: Time.current)
  end

  def to_gateway_payload
    {
      event: "ai_tagging.dispatch",
      run_id: id,
      asset_id: asset_id,
      asset_version_id: asset_version_id,
      profile: profile,
      instruction: profile_instruction,
      capability: "vision.tag",
      # Told to the gateway so it can stop early rather than sending us labels
      # we would only throw away — but re-applied on import regardless, because
      # a limit enforced only at the far end is not a limit.
      min_confidence: MIN_CONFIDENCE,
      max_suggestions: MAX_SUGGESTIONS,
      options: options,
      callback_url: Rails.application.routes.url_helpers
                         .suggestions_api_v1_ai_tagging_run_url(self, host: callback_host),
    }
  end

  private

  def callback_host
    Rails.application.credentials.dig(:app, :host).presence ||
      ENV.fetch("APP_HOST", "http://localhost:3000")
  end
end
