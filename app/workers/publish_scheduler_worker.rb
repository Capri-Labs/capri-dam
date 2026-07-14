# Sidekiq worker that applies due {ScheduledPublishAction} rows — the
# "Publish Later"/"Unpublish Later" options in the Explorer's Manage Publish
# menu (see ExplorerTopBar). Immediate Publish/Unpublish never touches this
# worker; only requests with a future +scheduled_at+ create a row here.
#
# == Schedule
#
# Polls every 5 minutes (see +config/schedule.rb+) rather than using
# +perform_at+/+perform_in+ per-request, so a still-pending row created for a
# time in the past (e.g. the app was down, or a clock skew) is picked up on
# the very next run instead of being silently missed.
#
# == Queue & retries
#
# * Queue:   +publishing+
# * Retries: 3 — publish/unpublish is a simple, idempotent column update, so
#   a brief DB blip is worth retrying automatically; {ScheduledPublishAction#apply!}
#   still marks the row +failed+ (with the error message) before re-raising,
#   so admins can see what happened even if all retries are exhausted.
#
# @see ScheduledPublishAction
# @see Asset#publish! Asset#unpublish!
class PublishSchedulerWorker
  include Sidekiq::Worker
  sidekiq_options queue: "publishing", retry: 3

  def perform
    ScheduledPublishAction.due.find_each do |scheduled_action|
      scheduled_action.apply!
    rescue StandardError => e
      # #apply! already persisted the failure; just log and keep processing
      # the rest of the batch instead of letting one bad row abort the run.
      Rails.logger.error(
        "[PublishScheduler] Failed to apply ##{scheduled_action.id} " \
        "(#{scheduled_action.action_type} asset=#{scheduled_action.asset_id}): #{e.message}"
      )
    end
  end
end
