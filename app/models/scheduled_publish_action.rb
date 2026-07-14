# Represents a user-scheduled "Publish Later" / "Unpublish Later" request for
# an {Asset}. Created by {Api::V1::AssetsController#publish}/{#unpublish} when
# the caller passes a future +scheduled_at+; applied by {PublishSchedulerWorker}
# once that time has passed.
#
# @see Asset#publish! Asset#unpublish!
# @see PublishSchedulerWorker
class ScheduledPublishAction < ApplicationRecord
  belongs_to :asset
  belongs_to :created_by, class_name: "User"

  enum :status, { pending: 0, completed: 1, cancelled: 2, failed: 3 }, default: :pending

  ACTION_TYPES = %w[publish unpublish].freeze

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :scheduled_at, presence: true

  scope :due, -> { pending.where(scheduled_at: ..Time.current) }

  # Applies the scheduled action to the associated asset and marks this
  # record +completed+ (or +failed+, re-raising the original error so
  # Sidekiq retry/reporting still functions normally for the caller).
  #
  # @return [void]
  def apply!
    case action_type
    when "publish"   then asset.publish!
    when "unpublish" then asset.unpublish!
    end
    update!(status: :completed, executed_at: Time.current)
  rescue StandardError => e
    update!(status: :failed, executed_at: Time.current, error_message: e.message)
    raise
  end
end
