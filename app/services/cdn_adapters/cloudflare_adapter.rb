require "net/http"
require "uri"
require "json"

module CdnAdapters
  class CloudflareAdapter < BaseAdapter
    # 🚀 ADVANCED: Cloudflare strictly limits tag purging to 30 tags per request.
    # We define this constant to automatically chunk large folder purges.
    MAX_TAGS_PER_REQUEST = 30

    def initialize(credentials)
      super
      @api_token = credentials.fetch(:api_token)
      @zone_id = credentials.fetch(:zone_id)
      @base_url = "https://api.cloudflare.com/client/v4/zones/#{@zone_id}/purge_cache"

      @account_id = credentials.fetch(:account_id)
      @kv_namespace = credentials.fetch(:kv_namespace)
      @kv_base_url = "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/storage/kv/namespaces/#{@kv_namespace}/values"
    end

    def sync_metadata(uuid, json_payload)
      # Cloudflare Endpoint: PUT /client/v4/accounts/{account_id}/storage/kv/namespaces/{namespace_id}/values/{key}
      uri = URI("#{@kv_base_url}/asset-#{uuid}")

      request = Net::HTTP::Put.new(uri)
      request["Authorization"] = "Bearer #{@api_token}"
      request["Content-Type"] = "application/json"

      # Cloudflare KV simply takes the raw string payload
      request.body = json_payload

      execute_request(uri, request, "KV Metadata Sync (asset-#{uuid})")
    end

    def purge_tag(tag, options = {})
      # Keeps the codebase DRY by routing single tags through the batch processor
      purge_batch([ tag ], options)
    end

    def purge_batch(tags, options = {})
      return true if tags.empty?

      success = true
      uri = URI(@base_url)

      # 🚀 ADVANCED: Automatic batch slicing to respect operational API limits
      tags.each_slice(MAX_TAGS_PER_REQUEST) do |tag_batch|
        request = Net::HTTP::Post.new(uri)

        # Cloudflare uses standard Bearer token authentication
        request["Authorization"] = "Bearer #{@api_token}"
        request["Content-Type"] = "application/json"

        # The Cloudflare Enterprise Cache-Tag payload
        request.body = { tags: tag_batch }.to_json

        batch_success = execute_request(uri, request, "Batch Purge (#{tag_batch.size} tags)")

        # If any single chunk fails, we mark the whole operation as failed
        # so Sidekiq knows to retry the job.
        success = false unless batch_success
      end

      success
    end

    private

    def execute_request(uri, request, action_name)
      # Operational Governance: Strict timeouts prevent deadlocked Sidekiq threads
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 5, open_timeout: 5) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        # Cloudflare returns a 200 OK even for some logical errors,
        # so we MUST parse the JSON to check the internal 'success' boolean.
        parsed_response = JSON.parse(response.body)

        if parsed_response["success"]
          Rails.logger.info "✅ Cloudflare #{action_name} successful."
          true
        else
          Rails.logger.error "💥 Cloudflare #{action_name} API rejected: #{parsed_response["errors"]}"
          false
        end
      else
        Rails.logger.error "💥 Cloudflare #{action_name} HTTP failed: #{response.code} - #{response.body}"
        false
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "💥 Cloudflare #{action_name} timed out: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "💥 Cloudflare #{action_name} network error: #{e.message}"
      false
    end
  end
end
