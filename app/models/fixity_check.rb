# One verification of one version's stored bytes against the digest recorded
# when it was ingested.
#
# @see Fixity::Verifier the service that creates these
# @see FixityAuditWorker the scheduled sweep
class FixityCheck < ApplicationRecord
  # Only +passed+ means "these are the bytes we ingested". The other three are
  # deliberately not collapsed into a single "failed": they call for different
  # responses, and an operator paged for corruption should not arrive to find a
  # network timeout.
  STATUSES = %w[passed failed missing unreadable].freeze

  # A conclusive verdict about the bytes themselves. An +unreadable+ result is
  # excluded because the check never got far enough to have an opinion.
  CONCLUSIVE_STATUSES = %w[passed failed missing].freeze

  belongs_to :asset
  belongs_to :asset_version

  validates :status, inclusion: { in: STATUSES }
  validates :checked_at, presence: true

  scope :recent, -> { order(checked_at: :desc) }
  scope :failing, -> { where(status: %w[failed missing]) }

  # @return [Boolean] whether this check proves the bytes are intact
  def passed?
    status == "passed"
  end

  # @return [Boolean] whether this check reached a verdict at all
  def conclusive?
    CONCLUSIVE_STATUSES.include?(status)
  end
end
