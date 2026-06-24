# Provides non-destructive deletion behaviour for ActiveRecord models.
#
# Including this concern adds an +active+ scope, a +trashed+ scope, and the
# instance methods {#soft_delete}, {#restore}, and {#trashed?}.  Actual rows
# are **never** removed from the database; instead a +deleted_at+ timestamp is
# stamped, making the record invisible to the default +active+ scope while
# remaining fully recoverable.
#
# @example Include in a model
#   class Asset < ApplicationRecord
#     include SoftDeletable
#   end
#
#   asset.soft_delete        # stamps deleted_at
#   Asset.trashed            # => [asset]
#   asset.restore            # clears deleted_at
#   Asset.active             # normal query — excludes trashed records
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    # Returns records that have not been soft-deleted.
    # @return [ActiveRecord::Relation]
    scope :active, -> { where(deleted_at: nil) }

    # Returns records that have been soft-deleted.
    # @return [ActiveRecord::Relation]
    scope :trashed, -> { where.not(deleted_at: nil) }
  end

  # Soft-deletes the record by stamping +deleted_at+ with the current time.
  # The record remains in the database and can be recovered via {#restore}.
  #
  # @return [Boolean] +true+ if the update succeeded
  def soft_delete
    update(deleted_at: Time.current)
  end

  # Recovers a previously soft-deleted record by clearing +deleted_at+.
  #
  # @return [Boolean] +true+ if the update succeeded
  def restore
    update(deleted_at: nil)
  end

  # Returns +true+ when the record has been soft-deleted.
  #
  # @return [Boolean]
  def trashed?
    deleted_at.present?
  end
end