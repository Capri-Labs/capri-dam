module Auditable
  extend ActiveSupport::Concern

  included do
    after_create :log_create
    after_update :log_update
    after_destroy :log_destroy
  end

  private

  def log_create
    create_audit_log('create', saved_changes)
  end

  def log_update
    # Only log if actual data changed (excluding updated_at)
    filtered_changes = saved_changes.except('updated_at')
    create_audit_log('update', filtered_changes) if filtered_changes.any?
  end

  def log_destroy
    create_audit_log('destroy', attributes)
  end

  def create_audit_log(action, data)
    # We need to access the current_user. In Rails, we usually store this
    # in Current.user via a middleware.
    AuditLog.create!(
      user: Current.user,
      action: action,
      auditable_type: self.class.name,
      auditable_id: self.id,
      changes_data: data
    )
  end
end