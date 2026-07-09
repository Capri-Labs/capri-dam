module IngestionAdapters
  class Base
    attr_reader :batch, :credentials

    # ─── Provider Registry ────────────────────────────────────────────────────
    # Delegate to the canonical DamProviders registry (app/lib/dam_providers.rb)
    # so there is a single source of truth shared with the model layer.
    PROVIDER_LABELS = DamProviders::LABELS

    def initialize(batch, credentials = {})
      @batch       = batch
      @credentials = credentials.is_a?(Hash) ? credentials.transform_keys(&:to_s) : {}
    end

    # ─── Abstract Interface ───────────────────────────────────────────────────

    # Returns the next page of file references from the source system.
    # @param cursor [String, nil] opaque pagination cursor from previous call
    # @param limit  [Integer]    max records per page
    # @return [Hash] { files: [{identifier:, size:, original_name:, metadata:,
    #   raw_metadata: (optional, adapter-specific)}],
    #                  next_cursor: String|nil, has_more: Boolean }
    def fetch_next_chunk(cursor = nil, limit = 100)
      raise NotImplementedError, "#{self.class} must implement #fetch_next_chunk"
    end

    # Streams a remote file to a local tempfile, yielding each binary chunk to caller.
    # Caller uses chunks for live SHA-256 hashing without buffering the whole file.
    # @param file_identifier [String] opaque identifier returned by fetch_next_chunk
    # @yield [chunk] binary chunk
    # @return [String] absolute path of local tempfile (caller is responsible for deletion)
    def download_and_stream(file_identifier, &block)
      raise NotImplementedError, "#{self.class} must implement #download_and_stream"
    end

    # Verify the connector credentials are valid without pulling any assets.
    # @return [Hash] { success: Boolean, message: String }
    def test_connection
      raise NotImplementedError, "#{self.class} must implement #test_connection"
    end

    # ─── Shared HTTP Helpers ──────────────────────────────────────────────────

    protected

    # Performs an authenticated GET request and returns the parsed JSON body.
    # Raises on non-2xx responses.
    def get_json(url, extra_headers = {})
      uri      = URI.parse(url)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        req = Net::HTTP::Get.new(uri)
        default_headers.merge(extra_headers).each { |k, v| req[k] = v }
        http.request(req)
      end

      raise "HTTP #{response.code} from #{url}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end

    # Default Authorization header — most DAMs use Bearer tokens.
    # Override in subclasses that use Basic auth or custom headers.
    def default_headers
      {
        "Authorization" => "Bearer #{credentials["auth_token"]}",
        "Accept"        => "application/json",
        "Content-Type"  => "application/json",
        "User-Agent"    => "CapriDAM-Migrator/1.0",
      }
    end

    # Download a binary file via HTTP and write to a tempfile.
    # Yields each chunk if a block is given (for live SHA-256 hashing).
    def stream_http_file(url, extension = ".bin", &block)
      uri      = URI.parse(url)
      tempfile = Tempfile.new([ "migration_", extension ])
      tempfile.binmode

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        req = Net::HTTP::Get.new(uri)
        default_headers.each { |k, v| req[k] = v }

        http.request(req) do |response|
          response.read_body do |chunk|
            block.call(chunk) if block
            tempfile.write(chunk)
          end
        end
      end

      tempfile.rewind

      # Ruby's Tempfile registers a GC finalizer that unlinks the underlying
      # file as soon as the Tempfile *object* becomes unreachable — which
      # happens right after this method returns, since only the path string
      # (not the object) is handed back to the caller. Every caller in this
      # codebase already explicitly deletes the file when it's done with it
      # (ExtractionWorker, AssetProcessorWorker), so disable the finalizer
      # here to stop Ruby's GC from racing/deleting the file out from under
      # callers — this is especially critical when the path is handed off
      # across an async Sidekiq job boundary (MigrationCommitWorker →
      # AssetProcessorWorker), where enough time elapses for a GC cycle to
      # run and silently delete the file before the job ever reads it.
      ObjectSpace.undefine_finalizer(tempfile)
      tempfile.path
    ensure
      tempfile&.close
    end

    def endpoint
      credentials["endpoint"].to_s.chomp("/")
    end
  end
end
