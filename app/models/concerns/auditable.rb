# Automatically writes an {AuditLog} entry after every create, update, and
# destroy of the including model.
#
# Log entries are only created when a {Current.user} is set in the request
# context.  System-level operations (seeds, background jobs, rake tasks, tests)
# that run without a current user are silently skipped so that a missing user
# never causes a transaction rollback.
#
# == Impersonation non-repudiation
#
# When an admin is actively impersonating another user, {Current.true_user} is
# the real admin and {Current.user} is the impersonated account.  Both are
# recorded so that audit reviewers can reconstruct the true chain of custody.
#
# @example Include in a model
#   class User < ApplicationRecord
#     include Auditable
#   end
module Auditable
  extend ActiveSupport::Concern

  included do
    after_create  :log_create
    after_update  :log_update
    after_destroy :log_destroy
  end

  private

  def log_create
    create_audit_log("create", saved_changes)
  end

  def log_update
    filtered_changes = saved_changes.except("updated_at")
    create_audit_log("update", filtered_changes) if filtered_changes.any?
  end

  def log_destroy
    create_audit_log("destroy", attributes)
  end

  def create_audit_log(action, data)
    return if Current.user.nil?

    AuditLog.create!(
      user:           Current.user,
      true_user:      Current.true_user,
      impersonated:   Current.impersonating?,
      action:         action,
      auditable_type: self.class.name,
      auditable_id:   self.id,
      changes_data:   data,
      ip_address:     Current.ip_address,
      user_agent:     Current.user_agent,
    )
  end
end
