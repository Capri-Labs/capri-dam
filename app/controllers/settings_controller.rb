class SettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    # This renders app/views/settings/show.html.erb

    # Only fetch system accounts if the user is an admin
    if current_user.admin?
      @system_apps = Doorkeeper::Application.where(owner_id: nil)
    end
  end

  def update
    # Define which keys are safe for regular users
    safe_keys = ['notifications_enabled', 'theme_preference']

    # Only append administrative keys if the user is an admin
    if current_user.admin?
      safe_keys += ['site_name', 'max_file_size', 'allowed_mimes', 'keycloak_realm']
    end

    params.require(:settings).each do |key, value|
      if safe_keys.include?(key)
        Setting.set(key, value)
      end
    end

    redirect_to settings_path, notice: "Preferences updated successfully."
  end
end