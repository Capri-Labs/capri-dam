module IngestionAdapters
  class Base
    attr_reader :batch, :credentials

    def initialize(batch, credentials = {})
      @batch = batch
      @credentials = credentials
    end

    # @return [Array<Hash>] Returns an array of file metadata representing the next chunk of files
    def fetch_next_chunk(cursor_id, limit = 100)
      raise NotImplementedError, "#{self.class} must implement #fetch_next_chunk"
    end

    # Streams the file, yields chunks for hashing, and returns the final local tempfile path
    def download_and_stream(file_identifier, &block)
      raise NotImplementedError, "#{self.class} must implement #download_and_stream"
    end
  end
end