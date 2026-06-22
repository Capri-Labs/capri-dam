class StorageManager
  # ──────────────────────────────────────────────────────────
  # Provider → Adapter mapping
  # ──────────────────────────────────────────────────────────
  ADAPTERS = {
    'local'        => 'StorageAdapters::LocalStorageAdapter',
    'aws'          => 'StorageAdapters::S3Adapter',
    'cloudflare'   => 'StorageAdapters::R2Adapter',
    'digitalocean' => 'StorageAdapters::SpacesAdapter',
    'wasabi'       => 'StorageAdapters::WasabiAdapter',
    'backblaze'    => 'StorageAdapters::BackblazeAdapter',
    'google'       => 'StorageAdapters::GcsAdapter',
    'azure'        => 'StorageAdapters::AzureAdapter'
  }.freeze

  # ──────────────────────────────────────────────────────────
  # Build an adapter from a StorageBackend ActiveRecord object.
  # ──────────────────────────────────────────────────────────
  def self.adapter_for(backend)
    return local_adapter if backend.nil?
    klass_name = ADAPTERS[backend.provider_type.to_s]
    raise ArgumentError, "Unknown storage provider: '#{backend.provider_type}'" unless klass_name
    klass_name.constantize.new(backend.configuration.transform_keys(&:to_s))
  end

  # ──────────────────────────────────────────────────────────
  # Returns the currently active adapter, reading live config
  # from the Setting model (written to by Settings UI).
  # Cached per-process; call .reset_active_adapter! after saves.
  # ──────────────────────────────────────────────────────────
  def self.active_adapter
    @active_adapter ||= build_from_settings
  end

  def self.reset_active_adapter!
    @active_adapter = nil
  end

  # ──────────────────────────────────────────────────────────
  # Store a file and optionally trigger AI enrichment.
  # Usage:
  #   StorageManager.store!(file, path, content_type: 'image/jpeg',
  #                          ai_enrichment: { asset_uuid: asset.uuid })
  # ──────────────────────────────────────────────────────────
  def self.store!(file, path, options = {})
    ai_opts = options.delete(:ai_enrichment)
    stored_path = active_adapter.store(file, path, options)
    if ai_opts.present?
      active_adapter.trigger_ai_enrichment(
        ai_opts.merge(storage_path: stored_path, content_type: options[:content_type])
      )
    end
    stored_path
  end

  # ──────────────────────────────────────────────────────────
  # Presign a URL using the active adapter (falls back to cdn_url).
  # ──────────────────────────────────────────────────────────
  def self.presign_url(path, **opts)
    adapter = active_adapter
    adapter.supports_presigned_urls? ? adapter.presign_url(path, **opts) : adapter.cdn_url(path)
  end

  # ──────────────────────────────────────────────────────────
  # Migrate all AssetVersion records from one provider to another.
  # ──────────────────────────────────────────────────────────
  def self.migrate_assets!(from_provider:, to_provider:, dry_run: false)
    from_adapter = build_adapter_for_provider(from_provider)
    to_adapter   = build_adapter_for_provider(to_provider)
    migrated = 0
    failed   = []

    AssetVersion.find_each do |version|
      source_path = version.properties['storage_path']
      next if source_path.blank?
      begin
        unless dry_run
          file_data = read_file_from_adapter(from_adapter, source_path)
          next unless file_data
          new_path = to_adapter.store(
            StringIO.new(file_data), source_path,
            content_type: version.properties['content_type']
          )
          version.update_column(:properties, version.properties.merge('storage_path' => new_path))
        end
        migrated += 1
      rescue => e
        Rails.logger.error("[StorageManager] Migration failed for version #{version.id}: #{e.message}")
        failed << { version_id: version.id, path: source_path, error: e.message }
      end
    end

    { migrated: migrated, failed: failed, dry_run: dry_run }
  end

  private

  def self.build_from_settings
    provider = Setting.get('active_storage_provider').to_s.presence || 'local'
    config   = load_config_for_provider(provider)
    build_adapter(provider, config)
  rescue => e
    Rails.logger.error("[StorageManager] Failed to build active adapter: #{e.message}. Falling back to local.")
    local_adapter
  end

  def self.build_adapter_for_provider(provider)
    build_adapter(provider, load_config_for_provider(provider))
  end

  def self.build_adapter(provider, config)
    klass_name = ADAPTERS[provider.to_s]
    raise ArgumentError, "Unknown storage provider: '#{provider}'" unless klass_name
    klass_name.constantize.new(config)
  end

  def self.load_config_for_provider(provider)
    return {} if provider == 'local'
    raw = Setting.get("storage_config_#{provider}")
    raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : (JSON.parse(raw) rescue {})
  end

  def self.local_adapter
    StorageAdapters::LocalStorageAdapter.new({})
  end

  def self.read_file_from_adapter(adapter, path)
    if adapter.is_a?(StorageAdapters::LocalStorageAdapter)
      full_path = Rails.root.join('storage', 'dam', path)
      File.exist?(full_path) ? File.binread(full_path) : nil
    else
      url = adapter.supports_presigned_urls? ? adapter.presign_url(path, expires_in: 600) : adapter.url(path)
      require 'net/http'
      Net::HTTP.get(URI.parse(url))
    end
  end
end