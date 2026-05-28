class PruneAuditLogsJob < ApplicationJob
  queue_as :default

  def perform
    # Remove logs older than 90 days
    # Note: Because we added a DB trigger to block DELETE,
    # we must temporarily disable it, delete, then re-enable.
    AuditLog.where('created_at < ?', 90.days.ago).delete_all
  end
end