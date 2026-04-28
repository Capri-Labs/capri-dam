class StorageManager
  def self.adapter_for(backend)
    case backend.provider_type
    when 'local'
      StorageAdapters::LocalStorageAdapter.new(backend.configuration)
    when 'aws_s3'
      # We'll build this once you have S3 credentials
      # StorageAdapters::S3Adapter.new(backend.configuration)
      raise "S3 Adapter not implemented yet"
    else
      raise "Unknown storage provider: #{backend.provider_type}"
    end
  end
end