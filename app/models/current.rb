# Thread-local request context populated by ApplicationController before every
# action.  Consumed by {Auditable} callbacks and structured log formatters.
#
# == Impersonation awareness
#
# * +user+       — the *effective* user (may be an impersonated account).
# * +true_user+  — the *real* authenticated user; equals +user+ when no
#                  impersonation session is active.
# * +impersonating?+ — convenience predicate.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :true_user, :ip_address, :user_agent

  def impersonating?
    true_user.present? && user != true_user
  end
end
