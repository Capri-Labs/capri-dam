module StorageAdapters
  class LocalStorageAdapter < BaseAdapter
    def store(file, path)
      full_path = Rails.root.join('storage', 'dam', path)
      FileUtils.mkdir_p(File.dirname(full_path))

      # Move or copy the file to the local storage path
      File.open(full_path, 'wb') do |f|
        f.write(file.read)
      end

      full_path.to_s
    end

    def delete(path)
      full_path = Rails.root.join('storage', 'dam', path)
      File.delete(full_path) if File.exist?(full_path)
    end

    def url(path)
      # For local dev, we return a path that Rails can serve or an absolute path
      "/storage/dam/#{path}"
    end
  end
end