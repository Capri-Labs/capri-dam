module StorageAdapters
  class LocalStorageAdapter < BaseAdapter
    ROOT = -> { Rails.root.join('storage', 'dam') }

    def store(file, path, options = {})
      full_path = ROOT.call.join(path)
      FileUtils.mkdir_p(full_path.dirname)
      File.open(full_path, 'wb') { |f| f.write(file.read) }
      path
    end

    def delete(path)
      full_path = ROOT.call.join(path)
      File.delete(full_path) if File.exist?(full_path)
    end

    def url(path)
      "/api/v1/assets/local/#{path}"
    end

    # Local presign: issues a signed Rails URL valid for expires_in seconds.
    # Falls back to a plain serve path if verifier is unavailable.
    def presign_url(path, expires_in: 3600, method: :get, content_type: nil, filename: nil)
      signed = Rails.application.message_verifier(:storage_presign).generate(
        { path: path, method: method.to_s, exp: Time.current.to_i + expires_in },
        expires_in: expires_in.seconds
      )
      query = { token: signed }
      query[:filename] = filename if filename.present?
      "/api/v1/assets/local/#{path}?#{query.to_query}"
    rescue => e
      Rails.logger.warn("[LocalAdapter] Presign failed, falling back to plain URL: #{e.message}")
      url(path)
    end

    def exists?(path)
      File.exist?(ROOT.call.join(path))
    end

    def copy(source_path, dest_path)
      src  = ROOT.call.join(source_path)
      dest = ROOT.call.join(dest_path)
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.cp(src, dest)
      dest_path
    end

    def metadata(path)
      full_path = ROOT.call.join(path)
      return nil unless File.exist?(full_path)
      stat = File.stat(full_path)
      {
        size: stat.size,
        content_type: Marcel::MimeType.for(File.open(full_path), name: File.basename(path)),
        etag: Digest::MD5.file(full_path).hexdigest,
        last_modified: stat.mtime,
        metadata: {}
      }
    rescue => e
      Rails.logger.error("[LocalAdapter] metadata error: #{e.message}")
      nil
    end

    def list(prefix: '', limit: 100)
      base = ROOT.call.join(prefix)
      return [] unless base.exist?
      Dir.glob("#{base}/**/*")
         .reject { |f| File.directory?(f) }
         .first(limit)
         .map do |f|
           stat = File.stat(f)
           { key: Pathname.new(f).relative_path_from(ROOT.call).to_s, size: stat.size, last_modified: stat.mtime }
         end
    end

    def test_connection
      ROOT.call.mkpath
      { success: true, message: "Local storage ready at #{ROOT.call}" }
    rescue => e
      { success: false, error: e.message }
    end

    def supports_presigned_urls?
      true
    end
  end
end