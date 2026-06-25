# Storage abstraction layer for the Capri DAM platform.
#
# {StorageManager} is the single point of interaction between application code
# and the configured storage provider.  It hides all provider-specific details
# behind a uniform adapter interface so that swapping from (e.g.) local disk to
# AWS S3 is a one-line configuration change.
#
# == Supported providers
#
# | Key | Adapter class |
# |-----|---------------|
# | +local+        | {StorageAdapters::LocalStorageAdapter} |
# | +aws+          | {StorageAdapters::S3Adapter} |
# | +cloudflare+   | {StorageAdapters::R2Adapter} |
# | +digitalocean+ | {StorageAdapters::SpacesAdapter} |
# | +wasabi+       | {StorageAdapters::WasabiAdapter} |
# | +backblaze+    | {StorageAdapters::BackblazeAdapter} |
# | +google+       | {StorageAdapters::GcsAdapter} |
# | +azure+        | {StorageAdapters::AzureAdapter} |
#
# == Active adapter
#
# {.active_adapter} is lazily built from the +Setting+ model (written by the
# Settings UI) and cached per-process.  Call {.reset_active_adapter!} after
# persisting a new storage configuration so the next request picks up the
# change without a server restart.
#
# == Migration
#
# {.migrate_assets!} iterates every {AssetVersion} and copies physical files
# from one provider to another, optionally in +dry_run+ mode for a preview.
#
# @see StorageAdapters::BaseAdapter
class StorageManager
  # Provider key → fully-qualified adapter class name mapping.
  ADAPTERS = {
    "local"        => "StorageAdapters::LocalStorageAdapter",
    "aws"          => "StorageAdapters::S3Adapter",
    "cloudflare"   => "StorageAdapters::R2Adapter",
    "digitalocean" => "StorageAdapters::SpacesAdapter",
    "wasabi"       => "StorageAdapters::WasabiAdapter",
    "backblaze"    => "StorageAdapters::BackblazeAdapter",
    "google"       => "StorageAdapters::GcsAdapter",
    "azure"        => "StorageAdapters::AzureAdapter",
  }.freeze

  # Instantiates the appropriate adapter for the given {StorageBackend} record.
  #
  # Falls back to {StorageAdapters::LocalStorageAdapter} when +backend+ is +nil+.
  #
  # @param backend [StorageBackend, nil] the active backend configuration record
  # @return [StorageAdapters::BaseAdapter] a configured adapter instance
  # @raise [ArgumentError] when the backend's +provider_type+ is not in {ADAPTERS}
  def self.adapter_for(backend)
    return local_adapter if backend.nil?
    klass_name = ADAPTERS[backend.provider_type.to_s]
    raise ArgumentError, "Unknown storage provider: '#{backend.provider_type}'" unless klass_name
    klass_name.constantize.new(backend.configuration.transform_keys(&:to_s))
  end

  # Returns the lazily-initialised adapter built from application settings.
  #
  # The result is memoised per-process.  Call {.reset_active_adapter!} to
  # force a rebuild after the active storage provider is changed.
  #
  # @return [StorageAdapters::BaseAdapter]
  def self.active_adapter
    @active_adapter ||= build_from_settings
  end

  # Clears the memoised active adapter so the next call to {.active_adapter}
  # rebuilds from the current {Setting} values.
  #
  # @return [void]
  def self.reset_active_adapter!
    @active_adapter = nil
  end

  # Stores a file via the active adapter and optionally triggers AI enrichment.
  #
  # @example Store with AI enrichment
  #   StorageManager.store!(file, "assets/uuid/v1.jpg",
  #                          content_type: 'image/jpeg',
  #                          ai_enrichment: { asset_uuid: asset.uuid })
  #
  # @param file    [IO, StringIO] the file stream to store
  # @param path    [String]       the logical destination path
  # @param options [Hash]         passed to the adapter; +:ai_enrichment+ is
  #   consumed here and triggers the embedding pipeline
  # @return [String] the stored path as returned by the adapter
  def self.store!(file, path, options = {})
    ai_opts     = options.delete(:ai_enrichment)
    stored_path = active_adapter.store(file, path, options)
    if ai_opts.present?
      active_adapter.trigger_ai_enrichment(
        ai_opts.merge(storage_path: stored_path, content_type: options[:content_type])
      )
    end
    stored_path
  end

  # Returns a URL for the given path — a pre-signed URL when the active adapter
  # supports it, otherwise a plain CDN URL.
  #
  # @param path [String] the logical storage path
  # @param opts [Hash]   forwarded to +presign_url+ (e.g. +expires_in: 3600+)
  # @return [String] a time-limited or permanent public URL
  def self.presign_url(path, **opts)
    adapter = active_adapter
    adapter.supports_presigned_urls? ? adapter.presign_url(path, **opts) : adapter.cdn_url(path)
  end

  # Migrates all {AssetVersion} physical files from one storage provider to
  # another.
  #
  # Each version's +storage_path+ property is updated in place after the file
  # is successfully copied.  Failed versions are collected and returned rather
  # than raising, so that a single bad file does not abort a large migration.
  #
  # @param from_provider [String] source provider key (e.g. +"local"+)
  # @param to_provider   [String] destination provider key (e.g. +"aws"+)
  # @param dry_run       [Boolean] when +true+, counts what would be migrated
  #   without actually moving any files
  # @return [Hash] +{ migrated: Integer, failed: Array<Hash>, dry_run: Boolean }+
  def self.migrate_assets!(from_provider:, to_provider:, dry_run: false)
    from_adapter = build_adapter_for_provider(from_provider)
    to_adapter   = build_adapter_for_provider(to_provider)
    migrated     = 0
    failed       = []

    AssetVersion.find_each do |version|
      source_path = version.properties["storage_path"]
      next if source_path.blank?
      begin
        unless dry_run
          file_data = read_file_from_adapter(from_adapter, source_path)
          next unless file_data
          new_path = to_adapter.store(
            StringIO.new(file_data), source_path,
            content_type: version.properties["content_type"]
          )
          version.update_column(:properties, version.properties.merge("storage_path" => new_path))
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

  # @api private
  def self.build_from_settings
    provider = Setting.get("active_storage_provider").to_s.presence || "local"
    config   = load_config_for_provider(provider)
    build_adapter(provider, config)
  rescue => e
    Rails.logger.error("[StorageManager] Failed to build active adapter: #{e.message}. Falling back to local.")
    local_adapter
  end

  # @api private
  def self.build_adapter_for_provider(provider)
    build_adapter(provider, load_config_for_provider(provider))
  end

  # @api private
  def self.build_adapter(provider, config)
    klass_name = ADAPTERS[provider.to_s]
    raise ArgumentError, "Unknown storage provider: '#{provider}'" unless klass_name
    klass_name.constantize.new(config)
  end

  # Loads the JSON configuration stored in the +Setting+ model for the given provider.
  # @api private
  def self.load_config_for_provider(provider)
    return {} if provider == "local"
    raw = Setting.get("storage_config_#{provider}")
    raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : (JSON.parse(raw) rescue {})
  end

  # @api private
  def self.local_adapter
    StorageAdapters::LocalStorageAdapter.new({})
  end

  # Reads raw bytes from the given adapter.  For local storage, reads directly
  # from disk; for remote adapters, fetches via a pre-signed URL.
  # @api private
  def self.read_file_from_adapter(adapter, path)
    if adapter.is_a?(StorageAdapters::LocalStorageAdapter)
      full_path = Rails.root.join("storage", "dam", path)
      File.exist?(full_path) ? File.binread(full_path) : nil
    else
      url = adapter.supports_presigned_urls? ? adapter.presign_url(path, expires_in: 600) : adapter.url(path)
      require "net/http"
      Net::HTTP.get(URI.parse(url))
    end
  end
end
