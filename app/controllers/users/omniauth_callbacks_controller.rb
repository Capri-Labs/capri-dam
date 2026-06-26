# Handles OmniAuth callbacks for the Keycloak OpenID Connect provider.
#
# Flow:
#   1. Browser hits GET /users/auth/keycloak_openid (initiates redirect to Keycloak).
#   2. Keycloak authenticates the user and redirects back to
#      GET /users/auth/keycloak_openid/callback.
#   3. OmniAuth validates the token and populates +request.env["omniauth.auth"]+.
#   4. This controller calls {User.from_omniauth} to find-or-provision the user.
#   5. On success the user is signed in and redirected to the authenticated root.
#   6. On failure the user is redirected to the sign-in page with an error message.
#
# @see User.from_omniauth
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # ─── Success callback ─────────────────────────────────────────────────────

  def keycloak_openid
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      unless @user.active_for_authentication?
        flash[:alert] = t("devise.failure.account_deactivated")
        redirect_to new_user_session_path and return
      end

      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Keycloak") if is_navigational_format?
    else
      # Stash partial auth data so the failure page can give a helpful message.
      session["devise.keycloak_data"] = request.env["omniauth.auth"]
                                                 .except("extra")
                                                 .to_h
      redirect_to new_user_session_path,
                  alert: @user.errors.full_messages.join("\n")
    end
  rescue StandardError => e
    Rails.logger.error("[OmniauthCallbacks] Unexpected error: #{e.class}: #{e.message}")
    redirect_to new_user_session_path,
                alert: t("devise.omniauth_callbacks.failure",
                         kind: "Keycloak", reason: "an unexpected error occurred")
  end

  # ─── Failure callback ─────────────────────────────────────────────────────

  # Called by OmniAuth when the provider returns an error (e.g. user denied
  # consent, Keycloak is unavailable, state mismatch).
  def failure
    Rails.logger.warn("[OmniauthCallbacks] SSO failure: #{failure_message}")
    redirect_to new_user_session_path,
                alert: t("devise.omniauth_callbacks.failure",
                         kind: "Keycloak",
                         reason: failure_message.humanize)
  end
end
