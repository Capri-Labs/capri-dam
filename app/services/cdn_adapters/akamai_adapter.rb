require "akamai/edgegrid"
require "net/http"
require "uri"
require "json"

module CdnAdapters
  class AkamaiAdapter < BaseAdapter
    # 🚀 ADVANCED: Akamai CCU v3 allows up to 50,000 bytes per request payload.
    # To prevent payload overflow while maximizing batch size, we chunk at 1,000 tags.
    MAX_TAGS_PER_REQUEST = 1000

    def initialize(credentials)
      super
      @host = credentials.fetch(:host)

      # Required for EdgeKV routing
      @edgekv_namespace = credentials.fetch(:edgekv_namespace)

      # Initialize the EdgeGrid HTTP client with your API credentials
      @http = Akamai::Edgegrid::HTTP.new(
        address: @host,
        client_token: credentials.fetch(:client_token),
        client_secret: credentials.fetch(:client_secret),
        access_token: credentials.fetch(:access_token)
      )
    end

    def sync_metadata(uuid, json_payload, network: "production", group: "assets")
      # Akamai Endpoint: PUT /edgekv/v1/networks/{network}/namespaces/{namespace}/groups/{group_id}/items/{item_id}
      endpoint = URI("https://#{@host}/edgekv/v1/networks/#{network}/namespaces/#{@edgekv_namespace}/groups/#{group}/items/#{uuid}")

      request = Net::HTTP::Put.new(endpoint)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"

      # Akamai accepts the raw payload directly into the item value
      request.body = json_payload

      execute_request(request, "EdgeKV Metadata Sync (#{uuid})")
    end

    def purge_tag(tag, options = {})
      purge_batch([ tag ], options)
    end

    def purge_batch(tags, options = {})
      return true if tags.empty?

      success = true

      # 🚀 ADVANCED: Operational Governance Routing
      # Default to 'invalidate' (Soft Purge) to ensure edge nodes can serve stale
      # content while fetching updates, preventing origin traffic spikes.
      action = options.fetch(:hard_purge, false) ? "delete" : "invalidate"

      # Allow routing to the staging network for pre-production testing
      network = options.fetch(:network, "production")

      endpoint = URI("https://#{@host}/ccu/v3/#{action}/tag/#{network}")

      # Chunking the tags to respect payload limits
      tags.each_slice(MAX_TAGS_PER_REQUEST) do |tag_batch|
        request = Net::HTTP::Post.new(endpoint)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"

        # Akamai expects the payload under the "objects" key
        request.body = { objects: tag_batch }.to_json

        batch_success = execute_request(request, "Batch Purge (#{tag_batch.size} tags) [#{action.upcase}]")
        success = false unless batch_success
      end

      success
    end

    private

    def execute_request(request, action_name)
      # 🚀 The EdgeGrid HTTP client automatically handles the complex HMAC signing
      # and executes the request with standard Net::HTTP timeouts.
      @http.read_timeout = 5
      @http.open_timeout = 5

      response = @http.request(request)

      if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPCreated)
        parsed_response = JSON.parse(response.body)

        # Akamai returns an estimated seconds metric. Useful for logging.
        eta = parsed_response["estimatedSeconds"]
        Rails.logger.info "✅ Akamai #{action_name} successful. Edge sync ETA: #{eta}s."
        true
      else
        Rails.logger.error "💥 Akamai #{action_name} HTTP failed: #{response.code} - #{response.body}"
        false
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "💥 Akamai #{action_name} timed out: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "💥 Akamai #{action_name} network error: #{e.message}"
      false
    end
  end
end
