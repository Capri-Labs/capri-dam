require 'azure/storage/blob'
require 'openssl'
require 'base64'
require 'uri'
require 'time'

module StorageAdapters
  # Azure Blob Storage Adapter
  #
  # Uses the azure-storage-blob gem. Auth via account_name + account_key.
  # Presigning uses Shared Access Signature (SAS) tokens.
  #
  # Expected config keys:
  #   account_name   Azure storage account name
  #   account_key    Storage account key (secret) — base64-encoded
  #   container      Container name (equivalent to bucket)
  #   acl            "private" | "public-read" (sets container public access)
  #   cdn_base_url   (optional) Azure CDN or custom domain
  class AzureAdapter < BaseAdapter

    # ─────────────────────────────────────────────
    # CORE OPERATIONS
    # ─────────────────────────────────────────────

    def store(file, path, options = {})
      content_type = options[:content_type] || 'application/octet-stream'
      blob_client.create_block_blob(
        container_name,
        path,
        file,
        content_type: content_type,
        metadata: options[:metadata] || {}
      )
      path
    rescue Azure::Core::Http::HTTPError => e
      raise StorageAdapters::StorageError, "Azure store failed for '#{path}': #{e.message}"
    end

    def delete(path)
      blob_client.delete_blob(container_name, path)
    rescue Azure::Core::Http::HTTPError => e
      return nil if e.status_code == 404
      raise StorageAdapters::StorageError, "Azure delete failed for '#{path}': #{e.message}"
    end

    def url(path)
      if public_container?
        cdn_base = @config['cdn_base_url'].to_s.chomp('/')
        if cdn_base.present?
          "#{cdn_base}/#{path}"
        else
          "https://#{account_name}.blob.core.windows.net/#{container_name}/#{path}"
        end
      else
        presign_url(path, expires_in: 86_400)
      end
    end

    # ─────────────────────────────────────────────
    # PRESIGNED URLS — Azure SAS Tokens
    # ─────────────────────────────────────────────

    def presign_url(path, expires_in: 3600, method: :get, content_type: nil, filename: nil)
      now  = Time.now.utc
      exp  = (now + expires_in).strftime('%Y-%m-%dT%H:%M:%SZ')
      start = now.strftime('%Y-%m-%dT%H:%M:%SZ')

      permissions = (method.to_sym == :put) ? 'cw' : 'r'

      # Build the SAS string-to-sign
      # Format: signedPermissions + \n + signedStart + \n + signedExpiry + \n
      #         + canonicalizedResource + \n + ... (remaining optional fields)
      canonicalized_resource = "/blob/#{account_name}/#{container_name}/#{path}"

      string_to_sign = [
        permissions,                        # sp
        start,                              # st
        exp,                                # se
        canonicalized_resource,             # canonicalized resource
        '',                                 # signedIdentifier
        '',                                 # signedIP
        'https',                            # signedProtocol
        '2020-08-04',                       # signedVersion
        'b',                                # signedResource (b = blob)
        '',                                 # signedSnapshotTime
        '',                                 # rscc (Cache-Control)
        content_type.to_s,                  # rscd (Content-Disposition) — repurposed for content_type hint
        '',                                 # rsce (Content-Encoding)
        '',                                 # rscl (Content-Language)
        ''                                  # rsct (Content-Type)
      ].join("\n")

      signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest('SHA256', Base64.decode64(account_key), string_to_sign)
      )

      params = {
        'sv'  => '2020-08-04',
        'ss'  => 'b',
        'srt' => 'o',
        'sp'  => permissions,
        'se'  => exp,
        'st'  => start,
        'spr' => 'https',
        'sig' => signature
      }
      params['rscd'] = "attachment; filename=\"#{filename}\"" if filename.present?

      base_url = "https://#{account_name}.blob.core.windows.net/#{container_name}/#{path}"
      "#{base_url}?#{URI.encode_www_form(params)}"
    rescue => e
      raise StorageAdapters::StorageError, "Azure SAS generation failed: #{e.message}"
    end

    def supports_presigned_urls?
      true
    end

    # ─────────────────────────────────────────────
    # ADVANCED OPERATIONS
    # ─────────────────────────────────────────────

    def exists?(path)
      blob_client.get_blob_properties(container_name, path)
      true
    rescue Azure::Core::Http::HTTPError => e
      return false if e.status_code == 404
      raise
    end

    def copy(source_path, dest_path)
      source_url = "https://#{account_name}.blob.core.windows.net/#{container_name}/#{source_path}"
      blob_client.copy_blob_from_uri(container_name, dest_path, source_url)
      dest_path
    rescue Azure::Core::Http::HTTPError => e
      raise StorageAdapters::StorageError, "Azure copy failed: #{e.message}"
    end

    def metadata(path)
      props = blob_client.get_blob_properties(container_name, path)
      blob  = props[1]
      {
        size: blob.properties[:content_length].to_i,
        content_type: blob.properties[:content_type],
        etag: blob.properties[:etag]&.delete('"'),
        last_modified: blob.properties[:last_modified],
        metadata: blob.metadata || {}
      }
    rescue Azure::Core::Http::HTTPError => e
      return nil if e.status_code == 404
      raise
    end

    def list(prefix: '', limit: 100)
      blobs = blob_client.list_blobs(container_name, prefix: prefix, max_results: limit)
      blobs.map do |b|
        {
          key: b.name,
          size: b.properties[:content_length].to_i,
          last_modified: b.properties[:last_modified],
          etag: b.properties[:etag]&.delete('"')
        }
      end
    rescue Azure::Core::Http::HTTPError => e
      Rails.logger.error("[AzureAdapter] list failed: #{e.message}")
      []
    end

    def test_connection
      # Try listing blobs to verify access
      blob_client.list_blobs(container_name, max_results: 1)
      { success: true, message: "Connected to Azure container '#{container_name}' in account '#{account_name}'" }
    rescue Azure::Core::Http::HTTPError => e
      case e.status_code
      when 404 then { success: false, error: "Container '#{container_name}' not found." }
      when 403 then { success: false, error: "Access denied. Check your account key." }
      else          { success: false, error: "Azure error #{e.status_code}: #{e.message}" }
      end
    rescue => e
      { success: false, error: e.message }
    end

    private

    def blob_client
      @blob_client ||= Azure::Storage::Blob::BlobService.create(
        storage_account_name: account_name,
        storage_access_key: account_key
      )
    end

    def account_name
      @config['account_name'].to_s
    end

    def account_key
      @config['account_key'] || @config['secret_key']
    end

    def container_name
      @config['container'] || @config['bucket']
    end

    def public_container?
      @config['acl'].to_s == 'public-read'
    end
  end
end

