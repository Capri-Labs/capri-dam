class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  protect_from_forgery with: :null_session, if: -> { request.format.json? }

  before_action :set_current_context

  private

  # CUSTOM AUTH: Check for web login first, then fallback to API token
  def authenticate_hybrid!
    return if user_signed_in? # Accept Devise web session

    doorkeeper_authorize! # Enforce OAuth token if not on web
  end

  def set_current_context
    Current.user = current_user
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end
end
