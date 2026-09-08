# A single label a vision model proposed for an asset.
#
# THE CENTRAL RULE
# ----------------
# A suggestion is not a tag. It becomes one only when {#accept!} is called by a
# person, which is the only code path in the system that writes a machine-
# derived label into +assets.properties["tags"]+. Nothing in the ingestion
# pipeline may write there directly.
#
# The reason is that tags are load-bearing: people search on them, collections
# filter on them, and rights rules can key off them. A library whose vocabulary
# is a silent blend of curated and speculative terms cannot be trusted, and
# there is no cheap way to separate them again afterwards.
#
# WHY DISMISSED ROWS ARE KEPT
# ---------------------------
# A rejected suggestion is a decision, and deleting it would throw that decision
# away — the next run would propose the same label and a person would reject it
# again, forever. Dismissals are therefore retained and consulted when importing
# later runs.
class AiTagSuggestion < ApplicationRecord
  STATES = %w[pending accepted dismissed].freeze

  belongs_to :ai_tagging_run
  belongs_to :asset
  belongs_to :decided_by, class_name: "User", optional: true

  validates :label, presence: true, length: { maximum: 100 }
  validates :state, inclusion: { in: STATES }
  validates :confidence,
            numericality: {
              greater_than_or_equal_to: 0, less_than_or_equal_to: 1, allow_nil: true
            }

  scope :pending,   -> { where(state: "pending") }
  scope :accepted,  -> { where(state: "accepted") }
  scope :dismissed, -> { where(state: "dismissed") }

  # Labels are matched on, not just displayed, so they are compared in one
  # canonical form. Without this "Sunset", "sunset " and "sunset" are three
  # different tags that look like one.
  def self.normalise(label)
    label.to_s.strip.squeeze(" ").downcase
  end

  # Copies the label onto the asset. Idempotent: accepting twice must not
  # produce a duplicate tag, and the asset's existing tags are preserved.
  def accept!(user: nil)
    transaction do
      props = asset.properties.is_a?(Hash) ? asset.properties : {}
      tags  = Array(props["tags"]).map { |t| self.class.normalise(t) }

      unless tags.include?(label)
        asset.update!(properties: props.merge("tags" => tags + [ label ]))
      end

      update!(state: "accepted", decided_by: user, decided_at: Time.current)
    end
  end

  # Rejects the label. Deliberately does NOT remove it from the asset's tags: if
  # a person had separately typed that tag themselves, a dismissal here is about
  # the machine's guess, not about their decision.
  def dismiss!(user: nil)
    update!(state: "dismissed", decided_by: user, decided_at: Time.current)
  end

  def pending?
    state == "pending"
  end
end
