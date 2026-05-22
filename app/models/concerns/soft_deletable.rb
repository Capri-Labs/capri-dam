module SoftDeletable
  extend ActiveSupport::Concern

  included do
    # Default scopes can be tricky, so we use explicit scopes.
    # When querying normally, always append .active
    scope :active, -> { where(deleted_at: nil) }
    scope :trashed, -> { where.not(deleted_at: nil) }
  end

  def soft_delete
    update(deleted_at: Time.current)
  end

  def restore
    update(deleted_at: nil)
  end

  def trashed?
    deleted_at.present?
  end
end