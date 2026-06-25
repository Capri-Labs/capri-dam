require "google/cloud/storage"

module StorageAdapters
  # Google Cloud Storage Adapter
  #
  # Uses the official google-cloud-storage gem.
  # Auth can be provided as a JSON credentials string (service account) or
  # via Application Default Credentials (ADC) for GCP-hosted environments.
  #
  # Expected config keys:
  #   project_id        GCP project ID
  #   credentials_json  Service account JSON (string or path to file)
  #   bucket            GCS bucket name
  #   acl               "private" | "public" | "publicRead" (default: "private")
  #   cdn_base_url      (optional) Cloud CDN or custom domain URL
  class GcsAdapter < BaseAdapter
    # ─────────────────────────────────────────────
    # CORE OPERATIONS
    # ─────────────────────────────────────────────

    def store(file, path, options = {})
      gcs_file = gcs_bucket.create_file(
        file,
        path,
        content_type: options[:content_type],
        cache_control: options[:cache_control] || "public, max-age=31536000",
        acl: gcs_acl(options[:acl]),
        metadata: options[:metadata] || {}
      )
      gcs_file.name
    rescue Google::Cloud::Error => e
      raise StorageAdapters::StorageError, "GCS store failed for '#{path}': #{e.message}"
    end

    def delete(path)
      gcs_bucket.file(path)&.delete
    rescue Google::Cloud::NotFoundError
      nil
    rescue Google::Cloud::Error => e
      raise StorageAdapters::StorageError, "GCS delete failed for '#{path}': #{e.message}"
    end

    def url(path)
      if public_bucket?
        "https://storage.googleapis.com/#{bucket_name}/#{path}"
      else
        presign_url(path, expires_in: 86_400)
      end
    end

    # ─────────────────────────────────────────────
    # PRESIGNED URLS (Signed URLs via V4)
    # ─────────────────────────────────────────────

    def presign_url(path, expires_in: 3600, method: :get, content_type: nil, filename: nil)
      file = gcs_bucket.file(path)
      raise StorageAdapters::StorageError, "GCS: file '#{path}' not found for presigning" unless file

      sign_options = { method: method.to_s.upcase, expires: expires_in, version: :v4 }
      sign_options[:content_type] = content_type if content_type.present?

      signed_url = file.signed_url(**sign_options)

      if filename.present?
        uri = URI.parse(signed_url)
        params = URI.decode_www_form(uri.query || "")
        params << [ "response-content-disposition", "attachment; filename=\"#{filename}\"" ]
        uri.query = URI.encode_www_form(params)
        signed_url = uri.to_s
      end

      signed_url
    rescue Google::Cloud::Error => e
      raise StorageAdapters::StorageError, "GCS presign failed for '#{path}': #{e.message}"
    end

    def supports_presigned_urls?
      true
    end

    # ─────────────────────────────────────────────
    # ADVANCED OPERATIONS
    # ─────────────────────────────────────────────

    def exists?(path)
      !gcs_bucket.file(path).nil?
    rescue Google::Cloud::Error
      false
    end

    def copy(source_path, dest_path)
      source_file = gcs_bucket.file(source_path)
      raise StorageAdapters::StorageError, "GCS source file '#{source_path}' not found" unless source_file
      source_file.copy(dest_path)
      dest_path
    rescue Google::Cloud::Error => e
      raise StorageAdapters::StorageError, "GCS copy failed: #{e.message}"
    end

    def metadata(path)
      f = gcs_bucket.file(path)
      return nil unless f
      {
        size: f.size,
        content_type: f.content_type,
        etag: f.etag,
        last_modified: f.updated_at,
        metadata: f.metadata || {},
      }
    rescue Google::Cloud::Error
      nil
    end

    def list(prefix: "", limit: 100)
      gcs_bucket.files(prefix: prefix, max: limit).map do |f|
        { key: f.name, size: f.size, last_modified: f.updated_at, etag: f.etag }
      end
    rescue Google::Cloud::Error => e
      Rails.logger.error("[GcsAdapter] list failed: #{e.message}")
      []
    end

    def test_connection
      gcs_bucket # will raise if bucket doesn't exist or credentials are invalid
      { success: true, message: "Connected to GCS bucket '#{bucket_name}' in project '#{project_id}'" }
    rescue Google::Cloud::NotFoundError
      { success: false, error: "Bucket '#{bucket_name}' not found in project '#{project_id}'." }
    rescue Google::Cloud::PermissionDeniedError
      { success: false, error: "Permission denied. Ensure the service account has Storage Object Admin role." }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def storage_client
      @storage_client ||= begin
        creds = @config["credentials_json"]
        opts = { project_id: project_id }

        if creds.present?
          # Support both raw JSON string and file path
          if File.exist?(creds.to_s)
            opts[:credentials] = creds
          else
            # Parse inline JSON credentials
            opts[:credentials] = Google::Auth::ServiceAccountCredentials.make_creds(
              json_key_io: StringIO.new(creds),
              scope: "https://www.googleapis.com/auth/devstorage.full_control"
            )
          end
        end
        # Falls back to Application Default Credentials if no credentials given
        Google::Cloud::Storage.new(**opts)
      end
    end

    def gcs_bucket
      @gcs_bucket ||= storage_client.bucket(bucket_name, skip_lookup: false)
    end

    def project_id
      @config["project_id"].to_s
    end

    def bucket_name
      @config["bucket"].to_s
    end

    def public_bucket?
      @config["acl"].to_s == "public-read"
    end

    def gcs_acl(override = nil)
      acl = override || @config["acl"] || "private"
      case acl
      when "public-read", "public" then "publicRead"
      when "private"               then nil  # GCS default is private
      else acl
      end
    end
  end
end
