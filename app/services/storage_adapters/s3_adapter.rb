require 'aws-sdk-s3'

module StorageAdapters
  # Amazon S3 adapter. Also serves as the base for S3-compatible providers
  # (Cloudflare R2, DigitalOcean Spaces, Wasabi, Backblaze B2) via subclassing.
  #
  # Expected config keys:
  #   access_key, secret_key, region, bucket
  #   endpoint      (optional – for custom S3-compatible endpoints)
  #   acl           (optional – "private" | "public-read", default: "private")
  #   cdn_base_url  (optional – CDN hostname to prefix delivery URLs)
  class S3Adapter < BaseAdapter
    # ─────────────────────────────────────────────
    # CORE OPERATIONS
    # ─────────────────────────────────────────────

    def store(file, path, options = {})
      client.put_object(
        bucket: bucket,
        key: path,
        body: file,
        content_type: options[:content_type],
        cache_control: options[:cache_control] || 'public, max-age=31536000',
        acl: options[:acl] || acl_setting,
        metadata: stringify_metadata(options[:metadata] || {})
      )
      path
    rescue Aws::S3::Errors::ServiceError => e
      raise StorageError, "S3 store failed for '#{path}': #{e.message}"
    end

    def delete(path)
      client.delete_object(bucket: bucket, key: path)
    rescue Aws::S3::Errors::NoSuchKey
      nil # non-raising – idempotent delete
    rescue Aws::S3::Errors::ServiceError => e
      raise StorageError, "S3 delete failed for '#{path}': #{e.message}"
    end

    def url(path)
      if public_bucket?
        # Construct a direct public URL (no expiry)
        ep = @config['endpoint'].to_s.chomp('/')
        if ep.present?
          "#{ep}/#{bucket}/#{path}"
        else
          "https://#{bucket}.s3.#{region}.amazonaws.com/#{path}"
        end
      else
        # Private bucket – generate a 24-hour presigned URL by default
        presign_url(path, expires_in: 86_400)
      end
    end

    # ─────────────────────────────────────────────
    # PRESIGNED URLS
    # ─────────────────────────────────────────────

    def presign_url(path, expires_in: 3600, method: :get, content_type: nil, filename: nil)
      signer = Aws::S3::Presigner.new(client: client)

      case method.to_sym
      when :put
        opts = { bucket: bucket, key: path, expires_in: expires_in }
        opts[:content_type] = content_type if content_type.present?
        signer.presigned_url(:put_object, **opts)
      else # :get (default)
        opts = { bucket: bucket, key: path, expires_in: expires_in }
        opts[:response_content_disposition] = "attachment; filename=\"#{filename}\"" if filename.present?
        signer.presigned_url(:get_object, **opts)
      end
    rescue Aws::S3::Errors::ServiceError => e
      raise StorageError, "S3 presign failed for '#{path}': #{e.message}"
    end

    def supports_presigned_urls?
      true
    end

    # ─────────────────────────────────────────────
    # ADVANCED OPERATIONS
    # ─────────────────────────────────────────────

    def exists?(path)
      client.head_object(bucket: bucket, key: path)
      true
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      false
    end

    def copy(source_path, dest_path)
      client.copy_object(
        bucket: bucket,
        copy_source: "#{bucket}/#{source_path}",
        key: dest_path,
        acl: acl_setting
      )
      dest_path
    rescue Aws::S3::Errors::ServiceError => e
      raise StorageError, "S3 copy failed '#{source_path}' → '#{dest_path}': #{e.message}"
    end

    def metadata(path)
      resp = client.head_object(bucket: bucket, key: path)
      {
        size: resp.content_length,
        content_type: resp.content_type,
        etag: resp.etag&.delete('"'),
        last_modified: resp.last_modified,
        metadata: resp.metadata || {}
      }
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      nil
    end

    def list(prefix: '', limit: 100)
      resp = client.list_objects_v2(bucket: bucket, prefix: prefix, max_keys: limit)
      resp.contents.map do |obj|
        { key: obj.key, size: obj.size, last_modified: obj.last_modified, etag: obj.etag&.delete('"') }
      end
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error("[S3Adapter] list failed: #{e.message}")
      []
    end

    def test_connection
      client.head_bucket(bucket: bucket)
      { success: true, message: "Connected to '#{bucket}' in #{region}" }
    rescue Aws::S3::Errors::NotFound
      { success: false, error: "Bucket '#{bucket}' not found." }
    rescue Aws::S3::Errors::Forbidden
      { success: false, error: "Access denied. Check your credentials and bucket policy." }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def client
      @client ||= Aws::S3::Client.new(client_options)
    end

    def client_options
      opts = {
        region: region,
        access_key_id: @config['access_key'],
        secret_access_key: @config['secret_key'],
        force_path_style: force_path_style?
      }
      opts[:endpoint] = @config['endpoint'] if @config['endpoint'].present?
      opts
    end

    def bucket
      @config['bucket'].to_s
    end

    def region
      @config['region'].presence || default_region
    end

    # Subclasses override this to set provider-specific default region.
    def default_region
      'us-east-1'
    end

    def force_path_style?
      @config['endpoint'].present?
    end

    def acl_setting
      @config['acl'].presence || 'private'
    end

    def public_bucket?
      acl_setting == 'public-read'
    end

    def stringify_metadata(hash)
      hash.transform_keys(&:to_s).transform_values(&:to_s)
    end
  end

  # Convenience error class for all adapter failures
  StorageError = Class.new(StandardError)
end

