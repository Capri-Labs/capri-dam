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
#
# @see GraphqlController
# @see Api::V1::AssetsController
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  protect_from_forgery with: :null_session, if: -> { request.format.json? }

  before_action :set_current_context

  private

  # Authenticates the request by trying Devise first, then OAuth.
  #
  # Called as a +before_action+ in every protected controller.  Raises
  # +Doorkeeper::Errors::DoorkeeperError+ (rendered as 401) when neither
  # session nor bearer token is present.
  #
  # @return [void]
  def authenticate_hybrid!
    return if user_signed_in?
    doorkeeper_authorize!
  end

  # Stores the acting user, remote IP, and user-agent in the thread-local
  # {Current} object so that {Auditable} callbacks and structured log entries
  # can reference them without needing to pass them through the call stack.
  #
  # @return [void]
  def set_current_context
    Current.user       = current_user
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end
end
