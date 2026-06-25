require "net/http"
require "uri"
require "json"

module CdnAdapters
  class FastlyAdapter < BaseAdapter
    def initialize(credentials)
      super
      @api_key = credentials.fetch(:api_key)
      @service_id = credentials.fetch(:service_id)
      # Required to target the specific Edge Dictionary
      @dictionary_id = credentials.fetch(:dictionary_id)
      @base_url = "https://api.fastly.com/service/#{@service_id}"
    end

    # Purge a single tag (e.g., 'asset-uuid' or 'folder-123')
    def purge_tag(tag, options = {})
      # Fastly Endpoint: POST /service/{service_id}/purge/{surrogate_key}
      uri = URI("#{@base_url}/purge/#{tag}")
      request = Net::HTTP::Post.new(uri)

      setup_headers(request, options)

      execute_request(uri, request, "Tag Purge (#{tag})")
    end

    # 🚀 ADVANCED: Purge multiple tags in a single O(1) network request
    def purge_batch(tags, options = {})
      return true if tags.empty?

      # Fastly Endpoint: POST /service/{service_id}/purge
      uri = URI("#{@base_url}/purge")
      request = Net::HTTP::Post.new(uri)

      setup_headers(request, options)
      request["Content-Type"] = "application/json"
      request.body = { surrogate_keys: tags }.to_json

      execute_request(uri, request, "Batch Purge (#{tags.size} tags)")
    end

    def sync_metadata(uuid, json_payload)
      # Fastly Endpoint: PUT /service/{service_id}/dictionary/{dictionary_id}/item/{item_key}
      uri = URI("#{@base_url}/dictionary/#{@dictionary_id}/item/#{uuid}")

      request = Net::HTTP::Put.new(uri)
      request["Fastly-Key"] = @api_key
      request["Accept"] = "application/json"

      # Fastly Edge Dictionaries expect form-urlencoded data for item values
      request.set_form_data({ "item_value" => json_payload })

      execute_request(uri, request, "Metadata Sync (#{uuid})")
    end

    private

    def setup_headers(request, options)
      request["Fastly-Key"] = @api_key
      request["Accept"] = "application/json"

      # 🚀 ADVANCED: Soft Purge Implementation
      # If true, Fastly serves stale content while re-fetching from the Rails origin
      if options.fetch(:soft_purge, true)
        request["Fastly-Soft-Purge"] = "1"
      end
    end

    def execute_request(uri, request, action_name)
      # Operational Governance: Strict timeouts prevent deadlocked workers
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 5, open_timeout: 5) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        Rails.logger.info "✅ Fastly #{action_name} successful."
        true
      else
        Rails.logger.error "💥 Fastly #{action_name} failed: #{response.code} - #{response.body}"
        false
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "💥 Fastly #{action_name} timed out: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "💥 Fastly #{action_name} network error: #{e.message}"
      false
    end
  end
end
