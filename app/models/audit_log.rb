# Immutable record of every create / update / destroy performed on an
# {Auditable} model, and of administrative actions (impersonation grants,
# password resets, etc.) recorded via {.record}.
#
# == Non-repudiation during impersonation
#
# When an admin is impersonating a user:
# * +user_id+      — the impersonated account (actions appear "by" them).
# * +true_user_id+ — the real admin who clicked the button.
# * +impersonated+ — true so security reviews can filter these rows.
#
# @see Auditable
# @see Current
class AuditLog < ApplicationRecord
  belongs_to :user
  belongs_to :true_user, class_name: "User", optional: true

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Record an explicit administrative action that falls outside the automatic
  # {Auditable} callbacks (e.g. impersonation grant/revoke, manual password
  # resets, token revocations).
  #
  # @param action [String]
  # @param auditable [ActiveRecord::Base] the object the action was taken on
  # @param user [User, nil] actor; defaults to {Current.user}
  # @param changes_data [Hash] arbitrary serialisable payload
  # @return [AuditLog, nil] nil when no user context is available
  def self.record(action:, auditable:, user: nil, changes_data: {})
    actor = user || Current.user
    return nil if actor.nil?

    create!(
      user:           actor,
      true_user:      Current.true_user,
      impersonated:   Current.impersonating?,
      action:         action,
      auditable_type: auditable.class.name,
      auditable_id:   auditable.id,
      changes_data:   changes_data,
      ip_address:     Current.ip_address,
      user_agent:     Current.user_agent,
    )
  end
end
