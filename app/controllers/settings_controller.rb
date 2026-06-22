require 'aws-sdk-s3'

class SettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    @active_view = 'System Ops'
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
    StorageManager::ADAPTERS.keys.reject { |p| p == 'local' }.each do |p|
      raw_val = Setting.get("storage_config_#{p}")
      raw = if raw_val.is_a?(Hash)
              raw_val.transform_keys(&:to_s)
            elsif raw_val.is_a?(String)
              begin JSON.parse(raw_val) rescue {} end
            else
              {}
            end
      # Mask all secret-like keys before sending to React
      raw.each_key { |k| raw[k] = '********' if k.to_s.downcase.match?(/secret|key|password|token|credentials/) && raw[k].present? }
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
    new_data  = params[:storage_config].except(:provider).to_h

    # 1. Load existing config from DB
    existing_raw = Setting.get("storage_config_#{provider}")
    existing_data = if existing_raw.is_a?(Hash)
                      existing_raw.transform_keys(&:to_s)
                    elsif existing_raw.is_a?(String)
                      JSON.parse(existing_raw) rescue {}
                    else
                      {}
                    end

    # 2. Merge new values, skipping masked placeholders and blank values
    new_data.each do |key, value|
      existing_data[key.to_s] = value unless value.to_s.strip == '********' || value.blank?
    end

    # 3. Persist and set as active provider
    Setting.set("active_storage_provider", provider)
    Setting.set("storage_config_#{provider}", existing_data.to_json)

    # 4. Sync to StorageBackend model so workers using adapter_for() pick up changes
    sync_to_storage_backend!(provider, existing_data)

    # 5. Bust the cached active adapter so the next request re-reads from DB
    StorageManager.reset_active_adapter!

    render json: { message: "Configuration for #{provider.upcase} saved and activated!" }, status: :ok
  rescue => e
    render json: { error: "Failed to save settings: #{e.message}" }, status: :unprocessable_entity
  end

  def test_connection
    config   = params[:storage_config].to_h.transform_keys(&:to_s)
    provider = config['provider'].to_s

    # Unmask secrets: if user sent '********', pull the real value from DB
    unmask_secrets!(provider, config)

    result = case provider
             when 'local'
               StorageAdapters::LocalStorageAdapter.new({}).test_connection
             when 'google'
               StorageAdapters::GcsAdapter.new(config).test_connection
             when 'azure'
               StorageAdapters::AzureAdapter.new(config).test_connection
             else
               # All S3-compatible providers share the same test logic
               adapter_klass = StorageManager::ADAPTERS[provider]&.constantize
               if adapter_klass
                 adapter_klass.new(config).test_connection
               else
                 { success: false, error: "Unknown provider: #{provider}" }
               end
             end

    if result[:success]
      render json: { success: true, message: result[:message] }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  # Replace masked placeholder values with stored real values before running tests
  def unmask_secrets!(provider, config)
    return if provider == 'local'
    stored_raw = Setting.get("storage_config_#{provider}")
    stored = stored_raw.is_a?(Hash) ? stored_raw.transform_keys(&:to_s) : (JSON.parse(stored_raw) rescue {})

    config.each_key do |k|
      if config[k].to_s.strip == '********'
        config[k] = stored[k.to_s]
      end
    end
  end

  # Keep StorageBackend model in sync so workers using adapter_for(backend) work correctly
  def sync_to_storage_backend!(provider, config)
    backend = StorageBackend.find_or_initialize_by(provider_type: provider)
    # Deactivate all other backends first
    StorageBackend.where.not(provider_type: provider).update_all(active: false)

    backend.name          = provider.humanize
    backend.configuration = config
    backend.active        = true
    backend.save!
  rescue => e
    Rails.logger.warn("[SettingsController] StorageBackend sync failed: #{e.message}")
  end
end