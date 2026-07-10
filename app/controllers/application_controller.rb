# Base controller for the Capri DAM application.
#
# Responsibilities:
# * Restricts HTML responses to modern browsers (via +allow_browser+).
# * Disables CSRF for JSON requests (API clients use OAuth tokens instead).
# * Populates the thread-local {Current} context before every action so that
#   {Auditable} callbacks can record the actor without any extra controller
#   plumbing.
#
# == Authentication strategy
#
# The protected endpoints use {#authenticate_hybrid!} which accepts **either**:
# * a Devise web session (browser UI)
# * a Doorkeeper OAuth 2.0 bearer token (API / mobile / external clients)
# * a Personal Access Token (PAT) in the Authorization header
#
# == Impersonation
#
# When +session[:impersonated_user_id]+ is present and the stored admin ID
# matches +warden.user+, +current_user+ returns the *impersonated* account.
# The original admin is always accessible via +true_user+.  The {Current}
# context is populated with both so audit logs always record the real actor.
#
# @see GraphqlController
# @see Api::V1::AssetsController
class ApplicationController < ActionController::Base
  include Authorization

  allow_browser versions: :modern

  # CSRF is only skipped for requests that authenticate with an explicit
  # bearer credential (Doorkeeper OAuth token or Personal Access Token).
  # Browsers never attach the `Authorization` header automatically on
  # cross-site requests, so token-authenticated calls carry no CSRF risk.
  # JSON requests relying solely on the Devise session cookie still go
  # through +verify_authenticity_token+ — the SPA's shared fetch helper
  # already attaches the `X-CSRF-Token` header (see
  # app/javascript/utils/adminUtils.js), so this does not break the UI.
  protect_from_forgery with: :null_session, if: -> { request.format.json? && token_authenticated_request? }

  before_action :set_current_context

  # ---------------------------------------------------------------------------
  # Authentication helpers
  # ---------------------------------------------------------------------------

  # Returns the *effective* user — the impersonated account when an
  # impersonation session is active, otherwise the Devise/OAuth user.
  def current_user
    if (imp_id = session[:impersonated_user_id]) && warden_user
      @current_user ||= User.find_by(id: imp_id) || warden_user
    else
      @current_user ||= warden_user
    end
  end
  helper_method :current_user

  # Returns the *real* authenticated user regardless of impersonation.
  def true_user
    @true_user ||= warden_user
  end
  helper_method :true_user

  # Returns +true+ when the request is running inside an impersonation session.
  def impersonating?
    session[:impersonated_user_id].present? &&
      warden_user.present? &&
      current_user != warden_user
  end
  helper_method :impersonating?

  private

  # Authenticates the request by trying Devise first, then PAT, then OAuth.
  def authenticate_hybrid!
    return if user_signed_in?
    return if authenticate_pat!
    doorkeeper_authorize!
  end

  # True when the request supplies bearer credentials (a Doorkeeper OAuth
  # token or a Personal Access Token) rather than relying solely on the
  # ambient session cookie. Used to decide whether it is safe to skip CSRF
  # verification — see the +protect_from_forgery+ call above.
  #
  # @return [Boolean]
  def token_authenticated_request?
    doorkeeper_token.present? ||
      request.headers["Authorization"].to_s.start_with?("Bearer #{PersonalAccessToken::PREFIX}")
  end

  # Authenticates via a Personal Access Token sent in the Authorization header.
  #
  #   Authorization: Bearer dat_<token>
  #
  # @return [Boolean] true when a valid PAT was found
  def authenticate_pat!
    raw = request.headers["Authorization"]&.sub(/\ABearer\s+/, "")
    return false unless raw&.start_with?(PersonalAccessToken::PREFIX)

    user = PersonalAccessToken.authenticate(raw)
    if user
      sign_in(user, store: false)
      return true
    end
    false
  end

  # Stores the acting user, remote IP, and user-agent in the thread-local
  # {Current} object so that {Auditable} callbacks and structured log entries
  # can reference them without needing to pass them through the call stack.
  def set_current_context
    Current.user       = current_user
    Current.true_user  = true_user
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end

  # The raw Devise/warden user — bypasses impersonation logic.
  def warden_user
    @warden_user ||= warden.user
  end
end
