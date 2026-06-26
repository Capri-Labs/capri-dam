# Legacy alias kept for any jobs already enqueued in Sidekiq's queue.
# New code should use {BinPurgeWorker} directly.
#
# @deprecated Use {BinPurgeWorker} instead.
class TrashCleanupWorker
  include Sidekiq::Worker
  sidekiq_options queue: "bin_purge", retry: 0

  def perform
    Rails.logger.info("[TrashCleanupWorker] Delegating to BinPurgeWorker (legacy alias)")
    BinPurgeWorker.new.perform
  end
end
