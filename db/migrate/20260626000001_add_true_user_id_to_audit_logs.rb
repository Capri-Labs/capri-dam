# Adds non-repudiation columns to audit_logs so that when an admin is
# impersonating a user every action can be traced back to the real actor.
#
# * true_user_id  — the admin who actually performed the action; NULL when
#                   no impersonation session is active.
# * impersonated  — convenience boolean; true when true_user_id != user_id.
class AddTrueUserIdToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_logs, :true_user_id, :bigint
    add_column :audit_logs, :impersonated, :boolean, default: false, null: false

    add_index :audit_logs, :true_user_id, name: "index_audit_logs_on_true_user_id"
  end
end

