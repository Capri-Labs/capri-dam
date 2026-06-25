# Records impersonation grants between user accounts.
#
# Row semantics: "impersonator CAN act as user".
#
# == Behaviour
#
# * When user-B impersonates user-A all actions are attributed to user-A in
#   the audit log (making it appear user-A performed them).
# * An explicit audit entry is written at impersonation START and END so that
#   security reviews can reconstruct the impersonation window.
# * A user cannot grant themselves impersonation (enforced by validation).
#
# @see User#can_be_impersonated_by?
# @see User#impersonating_accounts
class UserImpersonator < ApplicationRecord
  belongs_to :user,         class_name: 'User'   # account being impersonated
  belongs_to :impersonator, class_name: 'User'   # account that can impersonate

  validates :user_id, uniqueness: { scope: :impersonator_id,
                                    message: "is already allowed to impersonate this account" }
  validate  :not_self_impersonation

  private

  def not_self_impersonation
    if user_id == impersonator_id
      errors.add(:base, "A user cannot impersonate themselves.")
    end
  end
end

