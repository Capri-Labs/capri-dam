module StorageAdapters
  # Cloudflare R2 Adapter
  #
  # R2 is fully S3-compatible. The only differences are:
  #   - Endpoint format: https://<account_id>.r2.cloudflarestorage.com
  #   - Region must be set to "auto"
  #   - No egress fees (great for public CDN delivery)
  #
  # Expected config keys (in addition to S3Adapter):
  #   account_id    REQUIRED – your Cloudflare account ID
  #   access_key    R2 Access Key ID
  #   secret_key    R2 Secret Access Key
  #   bucket        Bucket name
  #   cdn_base_url  (optional) Your custom domain / workers.dev URL for public delivery
  class R2Adapter < S3Adapter
    private

    def default_region
      'auto'
    end

    # R2 endpoint is derived from account_id if not explicitly set
    def client_options
      opts = super
      opts[:endpoint] ||= r2_endpoint
      opts
    end

    def r2_endpoint
      account_id = @config['account_id'].to_s.strip
      raise StorageError, "Cloudflare R2 requires an account_id" if account_id.blank?
      "https://#{account_id}.r2.cloudflarestorage.com"
    end

    # R2 path-style is always required
    def force_path_style?
      true
    end

    def test_connection
      result = super
      result[:message] = "Connected to Cloudflare R2 bucket '#{bucket}'" if result[:success]
      result
    end
  end
end

