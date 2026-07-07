# Periodically purges {AuditLog} rows older than the retention window.
#
# == Immutability trigger
#
# +audit_logs+ carries a Postgres trigger (+trigger_protect_audit_logs+, see
# +db/migrate/20260527142102_add_immutability_to_audit_logs.rb+) that raises
# on every UPDATE/DELETE, so that application code can never silently tamper
# with or lose an audit trail entry. Retention pruning is the one sanctioned
# exception to that rule, so this job must explicitly disable the trigger for
# the duration of the delete and always re-enable it afterwards — even if the
# delete raises — so the table is never left unprotected.
class PruneAuditLogsJob < ApplicationJob
  queue_as :default

  RETENTION_PERIOD = 90.days
  TRIGGER_NAME = "trigger_protect_audit_logs".freeze

  def perform
    disable_immutability_trigger!
    AuditLog.where("created_at < ?", RETENTION_PERIOD.ago).delete_all
  ensure
    enable_immutability_trigger!
  end

  private

  def disable_immutability_trigger!
    AuditLog.connection.execute("ALTER TABLE audit_logs DISABLE TRIGGER #{TRIGGER_NAME}")
  end

  def enable_immutability_trigger!
    AuditLog.connection.execute("ALTER TABLE audit_logs ENABLE TRIGGER #{TRIGGER_NAME}")
  end
end
