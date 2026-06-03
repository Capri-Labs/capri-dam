module IngestionAdapters
  class Factory
    def self.build(batch)
      # In a production environment, credentials would be pulled securely from a Vault or encrypted DB column
      credentials = batch.source_credentials

      case batch.source_type
      when 'legacy_s3'
        S3Adapter.new(batch, credentials)
      when 'ftp'
        FtpAdapter.new(batch, credentials) # Future proofing
      else
        raise ArgumentError, "Unknown extraction source type: #{batch.source_type}"
      end
    end
  end
end