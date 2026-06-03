require 'aws-sdk-s3'

module IngestionAdapters
  class S3Adapter < Base
    def client
      @client ||= Aws::S3::Client.new(
        region: credentials[:region],
        access_key_id: credentials[:access_key],
        secret_access_key: credentials[:secret_key]
      )
    end

    def fetch_next_chunk(cursor_id, limit = 100)
      # Idempotent pagination using the cursor (marker)
      response = client.list_objects_v2(
        bucket: credentials[:bucket],
        max_keys: limit,
        continuation_token: cursor_id
      )

      {
        files: response.contents.map { |obj| { identifier: obj.key, size: obj.size, original_name: obj.key.split('/').last } },
        next_cursor: response.next_continuation_token,
        has_more: response.is_truncated
      }
    end

    def download_and_stream(file_identifier)
      tempfile = Tempfile.new(['ingestion', File.extname(file_identifier)])
      tempfile.binmode

      client.get_object(bucket: credentials[:bucket], key: file_identifier) do |chunk|
        # Yield the chunk to the caller (the Job) so it can calculate the SHA-256 hash in real-time
        yield chunk if block_given?
        tempfile.write(chunk)
      end

      tempfile.rewind
      tempfile.path
    ensure
      tempfile.close
    end
  end
end