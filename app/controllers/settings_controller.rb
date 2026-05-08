class SettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    # This renders app/views/settings/show.html.erb

    # Only fetch system accounts if the user is an admin
    if current_user.admin?
      @system_apps = Doorkeeper::Application.where(owner_id: nil)
    end

    @active_provider = Setting.get('active_storage_provider') || 'local'

    @all_configs = {}
    ['aws', 'cloudflare', 'backblaze', 'wasabi', 'digitalocean', 'google'].each do |p|
      raw = JSON.parse(Setting.get("storage_config_#{p}") || "{}")
      # Mask secrets before sending to React
      raw['secret_key'] = '********' if raw['secret_key'].present?
      @all_configs[p] = raw
    end
    @current_config = Setting.get_provider_config(@active_provider)
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

  def update_storage
    provider = params[:storage_config][:provider]
    new_data = params[:storage_config].except(:provider)

    # 1. Fetch existing data from DB
    existing_raw = Setting.get("storage_config_#{provider}")
    existing_data = JSON.parse(existing_raw || "{}")

    # 2. Merge data, but ignore masked placeholders
    new_data.each do |key, value|
      unless value == "********" || value.blank?
        existing_data[key] = value
      end
    end

    # 3. Save the specific provider config AND set it as active
    Setting.set("active_storage_provider", provider)
    Setting.set("storage_config_#{provider}", existing_data.to_json)

    render json: { message: "Configuration for #{provider} updated!" }, status: :ok
  rescue => e
    render json: { error: "Failed to save settings: #{e.message}" }, status: :unprocessable_entity
  end
end