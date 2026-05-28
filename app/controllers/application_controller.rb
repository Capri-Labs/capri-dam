class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  protect_from_forgery with: :null_session, if: -> { request.format.json? }

  before_action :set_current_context

  private

  def set_current_context
    Current.user = current_user
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end
end
