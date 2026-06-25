module StorageAdapters
  # Backblaze B2 Adapter
  #
  # Backblaze B2 has an S3-compatible API (B2 S3-Compatible API).
  # Endpoint format: https://s3.<region>.backblazeb2.com
  #
  # NOTE: Backblaze uses "Application Key ID" as access_key and
  #       "Application Key" as secret_key. The key must have access to the bucket.
  #
  # Expected config keys:
  #   access_key    Application Key ID (NOT the Master Application Key)
  #   secret_key    Application Key
  #   region        e.g. "us-west-002", "eu-central-003"
  #   bucket        Bucket name
  #   cdn_base_url  (optional) Cloudflare CDN or B2 CDN URL
  class BackblazeAdapter < S3Adapter
    private

    def default_region
      "us-west-002"
    end

    def client_options
      opts = super
      opts[:endpoint] ||= backblaze_endpoint
      opts
    end

    def backblaze_endpoint
      "https://s3.#{region}.backblazeb2.com"
    end

    def force_path_style?
      true
    end

    def test_connection
      result = super
      result[:message] = "Connected to Backblaze B2 bucket '#{bucket}' in #{region}" if result[:success]
      result
    end
  end
end
