require 'aws-sdk-s3'

class SettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    # 1. Determine the sub-view based on the URL path safely
    if request.path.include?('system')
      if current_user.admin?
        @sub_view = 'System'
        # Retrieve and mask the actual database SMTP settings before sending to React
        @smtp_config = Setting.get('smtp_settings') || {}
        if @smtp_config['password'].present?
          @smtp_config = @smtp_config.dup
          @smtp_config['password'] = '********' # Mask secret on initial render
        end
      else
        redirect_to settings_path, alert: "Access denied: System operations are restricted to Administrators." and return
      end
    else
      @sub_view = 'General'
    end

    # 2. Only fetch system accounts if the user is an admin
    if current_user.admin?
      @system_apps = Doorkeeper::Application.where(owner_id: nil)
    end

    # 3. Retrieve Cloud Storage configuration settings safely
    @active_provider = Setting.get('active_storage_provider') || 'local'

    @all_configs = {}
    ['aws', 'cloudflare', 'backblaze', 'wasabi', 'digitalocean', 'google'].each do |p|
      # Resilient check: handle both legacy JSON string and modern YAML serialized hashes
      raw_val = Setting.get("storage_config_#{p}")
      raw = if raw_val.is_a?(Hash)
              raw_val
            elsif raw_val.is_a?(String)
              begin
                JSON.parse(raw_val)
              rescue JSON::ParserError
                {}
              end
            else
              {}
            end

      # Mask storage secrets before sending to React view state
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

  def test_connection
    config = params[:storage_config]

    # 1. Handle masked secrets
    # If they didn't change the secret, pull the real one from the DB
    secret = config[:secret_key]
    if secret == "********"
      stored_config = JSON.parse(Setting.get("storage_config_#{config[:provider]}") || "{}")
      secret = stored_config['secret_key']
    end

    # 2. Initialize a temporary S3 Client
    s3_options = {
      region: config[:region],
      access_key_id: config[:access_key],
      secret_access_key: secret,
      force_path_style: true # Required for R2, Wasabi, etc.
    }

    # Add custom endpoint if provided (R2, Wasabi, etc.)
    s3_options[:endpoint] = config[:endpoint] if config[:endpoint].present?

    begin
      s3 = Aws::S3::Client.new(s3_options)
      # 3. Attempt to 'touch' the bucket
      s3.head_bucket(bucket: config[:bucket])

      render json: { success: true, message: "Connection successful! Found bucket '#{config[:bucket]}'." }
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end
end