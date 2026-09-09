# frozen_string_literal: true

module Fixity
  # Recomputes the SHA-256 of a stored version and compares it with the digest
  # written at ingest.
  #
  # WHY THIS DOES NOT USE StorageManager.read_file_from_adapter
  # -----------------------------------------------------------
  # That helper returns the whole object as one String. Fixity is the one
  # operation guaranteed to touch the *largest* files in the estate — the
  # masters, the ProRes, the layered PSDs — and reading a 40 GB video into a
  # Sidekiq process to hash it would take the worker down long before it found
  # any corruption. The digest is therefore streamed in fixed-size chunks and
  # the bytes are discarded as they are consumed, so memory stays constant
  # regardless of asset size.
  #
  # WHY A MISSING CHECKSUM IS NOT A FAILURE
  # ---------------------------------------
  # Assets ingested before checksums were recorded, or through paths that never
  # computed one, have nothing to compare against. Reporting those as corrupt
  # would bury real corruption in false alarms on day one. They are reported
  # separately as *unverifiable* — a coverage gap to close, not an incident.
  class Verifier
    CHUNK_SIZE = 5.megabytes

    # Reading is capped so one pathological object cannot occupy a worker
    # indefinitely; the check is abandoned as +unreadable+, which is honest,
    # rather than being recorded as a verdict it never reached.
    READ_TIMEOUT = 300

    Result = Struct.new(:status, :check, :message, keyword_init: true) do
      def passed?
        status == "passed"
      end
    end

    class << self
      # @param asset_version [AssetVersion]
      # @return [Result, nil] nil when the version has nothing to compare to
      def call(asset_version)
        new(asset_version).call
      end
    end

    def initialize(asset_version)
      @asset_version = asset_version
      @asset = asset_version.asset
    end

    # @return [Result, nil]
    def call
      expected = expected_checksum
      return nil if expected.blank? || storage_path.blank?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = compute(expected)
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      record(outcome.merge(expected_checksum: expected, duration_ms: duration))
    end

    private

    attr_reader :asset_version, :asset

    def expected_checksum
      asset_version.properties.to_h["checksum_sha256"].presence
    end

    def storage_path
      asset_version.properties.to_h["storage_path"].presence
    end

    # @return [Hash] status plus whatever the read established
    def compute(expected)
      adapter = StorageManager.active_adapter

      unless object_present?(adapter)
        return { status: "missing", error_message: "No object at #{storage_path}" }
      end

      digest, bytes = stream_digest(adapter)

      if digest == expected
        { status: "passed", actual_checksum: digest, byte_size: bytes }
      else
        { status: "failed", actual_checksum: digest, byte_size: bytes,
          error_message: "Digest mismatch: expected #{expected}, read #{digest}" }
      end
    rescue StandardError => e
      # Deliberately broad. Every failure mode of remote storage — a refused
      # connection, an expired signature, a DNS blip — is inconclusive about the
      # file, and recording any of them as +failed+ would raise a corruption
      # alarm about a network problem.
      { status: "unreadable", error_message: "#{e.class}: #{e.message}" }
    end

    # +exists?+ is a HEAD, which is free compared with a full download, and it
    # separates "gone" from "corrupt" before spending any egress.
    def object_present?(adapter)
      return true unless adapter.respond_to?(:exists?)

      adapter.exists?(storage_path)
    rescue StandardError
      # An adapter that cannot answer must not be allowed to declare the object
      # missing; fall through and let the read decide.
      true
    end

    # @return [Array(String, Integer)] hex digest and byte count
    def stream_digest(adapter)
      sha = Digest::SHA256.new
      bytes = 0

      each_chunk(adapter) do |chunk|
        sha.update(chunk)
        bytes += chunk.bytesize
      end

      [ sha.hexdigest, bytes ]
    end

    def each_chunk(adapter, &block)
      if adapter.is_a?(StorageAdapters::LocalStorageAdapter)
        stream_local(&block)
      else
        stream_remote(adapter, &block)
      end
    end

    def stream_local
      full_path = StorageAdapters::LocalStorageAdapter::ROOT.call.join(storage_path)
      raise Errno::ENOENT, full_path.to_s unless File.exist?(full_path)

      File.open(full_path, "rb") do |io|
        while (chunk = io.read(CHUNK_SIZE))
          yield chunk
        end
      end
    end

    def stream_remote(adapter)
      require "net/http"

      url = if adapter.supports_presigned_urls?
              adapter.presign_url(storage_path, expires_in: READ_TIMEOUT * 2)
      else
              adapter.url(storage_path)
      end

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = READ_TIMEOUT

      http.start do |session|
        session.request(Net::HTTP::Get.new(uri)) do |response|
          raise "HTTP #{response.code} reading #{storage_path}" unless response.is_a?(Net::HTTPSuccess)

          response.read_body { |chunk| yield chunk }
        end
      end
    end

    def record(attrs)
      check = FixityCheck.create!(
        attrs.merge(
          asset_id: asset.id,
          asset_version_id: asset_version.id,
          storage_path: storage_path,
          storage_backend: current_backend,
          checked_at: Time.current,
        ),
      )

      # +update_columns+ rather than +update!+ so a verification sweep never
      # fires callbacks, touches updated_at, or reindexes the asset: a read-only
      # audit must not appear in the asset's history as an edit.
      asset_version.update_columns(
        last_fixity_check_at: check.checked_at,
        fixity_status: check.status,
      )

      Result.new(status: check.status, check: check, message: check.error_message)
    end

    def current_backend
      StorageManager.active_adapter.provider_name
    rescue StandardError
      nil
    end
  end
end
