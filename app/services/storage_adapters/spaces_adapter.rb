module StorageAdapters
  # DigitalOcean Spaces Adapter
  #
  # Spaces is S3-compatible. Endpoint format:
  #   https://<region>.digitaloceanspaces.com
  #
  # Expected config keys:
  #   access_key    Spaces access key
  #   secret_key    Spaces secret key
  #   region        e.g. "nyc3", "ams3", "sgp1", "fra1"
  #   bucket        Space name
  #   cdn_base_url  (optional) CDN endpoint e.g. https://<space>.cdn.digitaloceanspaces.com
  class SpacesAdapter < S3Adapter
    private

    def default_region
      "nyc3"
    end

    # Spaces endpoint is always region-based unless overridden
    def client_options
      opts = super
      opts[:endpoint] ||= spaces_endpoint
      opts
    end

    def spaces_endpoint
      "https://#{region}.digitaloceanspaces.com"
    end

    def force_path_style?
      false # Spaces uses virtual-hosted-style (bucket.region.digitaloceanspaces.com)
    end

    # For Spaces, the public URL is virtual-hosted style
    def url(path)
      if public_bucket?
        cdn_base = @config["cdn_base_url"].to_s.chomp("/")
        if cdn_base.present?
          "#{cdn_base}/#{path}"
        else
          "https://#{bucket}.#{region}.digitaloceanspaces.com/#{path}"
        end
      else
        presign_url(path, expires_in: 86_400)
      end
    end

    def test_connection
      result = super
      result[:message] = "Connected to DigitalOcean Space '#{bucket}' in #{region}" if result[:success]
      result
    end
  end
end
