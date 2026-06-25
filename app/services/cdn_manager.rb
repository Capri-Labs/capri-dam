class CdnManager
  def self.adapter
    # HIGHEST PRECEDENCE: The Encrypted Database (Production UI)
    active_config = CdnConfiguration.find_by(is_active: true)

    if active_config
      provider = active_config.provider
      credentials = active_config.settings.symbolize_keys
    else
      # FALLBACK PRECEDENCE: The YAML/ENV config (Local Dev & CI/CD)
      Rails.logger.info "ℹ️ No active CDN in database. Falling back to cdn_settings.yml"

      yaml_config = Rails.application.config_for(:cdn_settings)
      provider = yaml_config[:active_provider]
      credentials = yaml_config[provider.to_sym] if provider

      # 3. 🚀 FAIL-SAFE: Stop the worker if absolutely nothing is configured
      raise "FATAL: No CDN configured in Database or YAML." unless provider && credentials
    end

    # Route to the correct adapter
    case provider
    when "fastly"
      CdnAdapters::FastlyAdapter.new(credentials)
    when "cloudflare"
      CdnAdapters::CloudflareAdapter.new(credentials)
    when "akamai"
      CdnAdapters::AkamaiAdapter.new(credentials)
    else
      raise "Unknown CDN Provider: #{provider}"
    end
  end

  def self.sync_metadata(uuid, json_payload)
    adapter.sync_metadata(uuid, json_payload)
  end

  def self.purge_tag(tag, soft_purge: true)
    adapter.purge_tag(tag, soft_purge: soft_purge)
  end

  def self.purge_batch(tags, soft_purge: true)
    adapter.purge_batch(tags, soft_purge: soft_purge)
  end
end
