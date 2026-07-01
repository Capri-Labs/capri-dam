class InboxCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: "default", retry: 1

  def perform
    InboxMessage.active.read
                .where("read_at < ?", 90.days.ago)
                .update_all(archived_at: Time.current)

    InboxMessage.archived
                .where("archived_at < ?", 1.year.ago)
                .delete_all
  end
end
