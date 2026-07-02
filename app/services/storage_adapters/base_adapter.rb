module StorageAdapters
  StorageError = Class.new(StandardError) unless const_defined?(:StorageError)

  class BaseAdapter
    attr_reader :config

    def initialize(config = {})
      @config = config.is_a?(Hash) ? config.transform_keys(&:to_s) : {}
    end

    # ─────────────────────────────────────────────
    # CORE OPERATIONS (must be implemented)
    # ─────────────────────────────────────────────

    # Store a file at the given path. Returns the stored path.
    # options: { content_type:, metadata:, acl:, cache_control: }
    def store(file, path, options = {})
      raise NotImplementedError, "#{self.class}#store is not implemented"
    end

    # Permanently remove a file. Returns nil if not found (non-raising).
    def delete(path)
      raise NotImplementedError, "#{self.class}#delete is not implemented"
    end

    # Returns the canonical public/CDN URL for a stored path.
    def url(path)
      raise NotImplementedError, "#{self.class}#url is not implemented"
    end

    # ─────────────────────────────────────────────
    # ADVANCED OPERATIONS (implement in subclasses)
    # ─────────────────────────────────────────────

    # Returns a time-limited signed URL for secure (private) access.
    # method: :get (download) | :put (direct browser upload)
    # For PUT presigns, pass content_type so the signature is bound to it.
    def presign_url(path, expires_in: 3600, method: :get, content_type: nil, filename: nil)
      raise NotImplementedError, "#{self.class} does not support presigned URLs"
    end

    # Check if a file exists without downloading it.
    def exists?(path)
      raise NotImplementedError, "#{self.class}#exists? is not implemented"
    end

    # Server-side copy without re-downloading.
    def copy(source_path, dest_path)
      raise NotImplementedError, "#{self.class}#copy is not implemented"
    end

    # Move a file (default: copy + delete).
    def move(source_path, dest_path)
      copy(source_path, dest_path)
      delete(source_path)
      dest_path
    end

    # Return a metadata hash: { size:, content_type:, etag:, last_modified:, metadata: }
    def metadata(path)
      raise NotImplementedError, "#{self.class}#metadata is not implemented"
    end

    # List files under a prefix. Returns array of { key:, size:, last_modified: }.
    def list(prefix: "", limit: 100)
      raise NotImplementedError, "#{self.class}#list is not implemented"
    end

    # Verify connectivity and credentials. Returns { success: bool, message/error: }.
    def test_connection
      raise NotImplementedError, "#{self.class}#test_connection is not implemented"
    end

    # ─────────────────────────────────────────────
    # HELPERS (shared across all adapters)
    # ─────────────────────────────────────────────

    # Returns true if this adapter can issue presigned/signed URLs.
    def supports_presigned_urls?
      false
    end

    # Returns the human-readable provider name derived from the class name.
    def provider_name
      self.class.name.demodulize.underscore.delete_suffix("_adapter")
    end

    # Resolves the delivery URL: prefer CDN base URL if configured, else native url().
    def cdn_url(path)
      base = @config["cdn_base_url"].to_s.chomp("/")
      base.present? ? "#{base}/#{path}" : url(path)
    end

    # ─────────────────────────────────────────────
    # AI ENRICHMENT HOOK
    # ─────────────────────────────────────────────

    # Called after a successful store() when AI enrichment is requested.
    # Publishes an event to the Redis ai_gateway_events channel so the Python
    # FastAPI gateway can generate an embedding for the newly stored file.
    # options: { asset_uuid:, content_type:, storage_path: }
    def trigger_ai_enrichment(options = {})
      return unless options[:asset_uuid].present?

      payload = {
        event: "asset.needs_embedding",
        asset_uuid: options[:asset_uuid],
        storage_path: options[:storage_path],
        content_type: options[:content_type],
        provider: provider_name,
      }.to_json

      redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
      redis.publish("ai_gateway_events", payload)
    rescue => e
      Rails.logger.warn("[StorageAdapter] AI enrichment trigger failed: #{e.message}")
    end
  end
end
