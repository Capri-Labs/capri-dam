module StorageAdapters
  # Wasabi Hot Storage Adapter
  #
  # Wasabi is S3-compatible with zero egress fees.
  # Endpoint format: https://s3.<region>.wasabisys.com
  #
  # Expected config keys:
  #   access_key    Wasabi access key
  #   secret_key    Wasabi secret key
  #   region        e.g. "us-east-1", "eu-central-1", "ap-northeast-1"
  #   bucket        Bucket name
  #   cdn_base_url  (optional)
  class WasabiAdapter < S3Adapter
    private

    def default_region
      'us-east-1'
    end

    def client_options
      opts = super
      opts[:endpoint] ||= wasabi_endpoint
      opts
    end

    def wasabi_endpoint
      "https://s3.#{region}.wasabisys.com"
    end

    def force_path_style?
      true
    end

    def test_connection
      result = super
      result[:message] = "Connected to Wasabi bucket '#{bucket}' in #{region}" if result[:success]
      result
    end
  end
end

