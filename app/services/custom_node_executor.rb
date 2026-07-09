require "digest"
require "ipaddr"
require "openssl"
require "resolv"
require "uri"

# Executes a declarative custom workflow node by calling a customer-hosted HTTPS endpoint.
#
# Security rationale: custom-node definitions are manifests, not code. Capri DAM never evals,
# loads, or runs tenant code in-process. Runtime execution is an outbound, SSRF-guarded,
# HMAC-signed POST to the registered endpoint, and only a small whitelist of response actions
# is applied to the asset. Failures trip a circuit breaker and fail open to the next linear
# workflow edge so one bad plugin cannot wedge the workflow engine.
class CustomNodeExecutor
  DEFAULT_TIMEOUT_MS = 5_000
  SENSITIVE_CONFIG_KEYS = /secret|token|password|credential|api[_-]?key/i
  BLOCKED_IP_RANGES = [
    "0.0.0.0/8",
    "10.0.0.0/8",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "224.0.0.0/4",
    "::1/128",
    "fc00::/7",
    "fe80::/10",
  ].map { |range| IPAddr.new(range) }.freeze

  def initialize(instance, step, config)
    @instance = instance
    @step = step
    @config = (config || {}).with_indifferent_access
    @asset = instance.asset
  end

  # @return [Array(Symbol, String), nil] +[:branch, handle]+ for branching plugin responses; +nil+ otherwise.
  def call
    key = @step.node_type.to_s.delete_prefix("plugin:")
    definition = CustomNodeDefinition.enabled.find_by(key: key)
    return missing_definition(key) unless definition
    return circuit_open(definition) if definition.circuit_open?

    endpoint = definition.runtime["endpoint_url"].to_s
    validate_endpoint!(endpoint)
    response = post_definition(definition, endpoint, payload_for(key))
    return record_failure(definition, "HTTP #{response.status}") unless response.success?

    apply_response(definition, response.body)
  rescue URI::InvalidURIError, Resolv::ResolvError, Faraday::Error, Timeout::Error, SocketError => e
    record_failure(definition, e.message) if definition
    nil
  end

  private

  def missing_definition(key)
    Rails.logger.warn("[CustomNodeExecutor] Missing or disabled custom node '#{key}' — skipping")
    nil
  end

  def circuit_open(definition)
    Rails.logger.warn("[CustomNodeExecutor] Circuit open for custom node '#{definition.key}' — skipping")
    nil
  end

  def payload_for(key)
    {
      event: "workflow.custom_node",
      workflow_id: @instance.workflow_id,
      instance_id: @instance.id,
      step: @step.title,
      node_key: key,
      config: sanitized_config,
      asset: {
        id: @asset.id,
        title: @asset.title,
        status: @asset.status,
        properties: @asset.properties || {},
      },
    }
  end

  def sanitized_config
    @config.to_h.deep_stringify_keys.reject { |key, _value| key.match?(SENSITIVE_CONFIG_KEYS) }
  end

  def post_definition(definition, endpoint, payload)
    body = payload.to_json
    headers = {
      "Content-Type" => "application/json",
      "X-Capri-Signature" => hmac_signature(definition, body),
    }
    timeout = timeout_seconds(definition.runtime["timeout_ms"])

    Faraday.new { |conn| conn.options.timeout = timeout }
           .post(endpoint, body, headers)
  end

  def hmac_signature(definition, body)
    OpenSSL::HMAC.hexdigest("SHA256", secret_for(definition), body)
  end

  def secret_for(definition)
    runtime = definition.runtime || {}
    runtime["secret"].presence || credentials_secret(runtime["secret_ref"]).to_s
  end

  def credentials_secret(secret_ref)
    return nil if secret_ref.blank?

    path = secret_ref.to_s.split(".").map(&:to_sym)
    Rails.application.credentials.dig(*path)
  end

  def timeout_seconds(timeout_ms)
    (timeout_ms.presence || DEFAULT_TIMEOUT_MS).to_i.clamp(1, 30_000) / 1000.0
  end

  def validate_endpoint!(endpoint)
    uri = URI.parse(endpoint)
    raise URI::InvalidURIError, "custom node endpoint must be https" unless uri.is_a?(URI::HTTPS)
    raise URI::InvalidURIError, "custom node endpoint host missing" if uri.host.blank?

    ips = resolved_ips(uri.host)
    raise URI::InvalidURIError, "custom node endpoint could not be resolved" if ips.empty?

    ips.each do |ip|
      raise URI::InvalidURIError, "custom node endpoint resolves to a private address" if blocked_ip?(ip)
    end
  end

  def resolved_ips(host)
    ipaddr = IPAddr.new(host) rescue nil
    return [ ipaddr ] if ipaddr

    Resolv.getaddresses(host).map { |address| IPAddr.new(address) }
  end

  def blocked_ip?(ip)
    BLOCKED_IP_RANGES.any? { |range| range.include?(ip) }
  end

  def apply_response(definition, body)
    actions = JSON.parse(body.presence || "{}")
    branch = actions["branch"].presence
    apply_asset_actions(actions)
    definition.update!(failure_count: 0, last_error: nil, last_dispatched_at: Time.current)
    branch ? [ :branch, branch.to_s ] : nil
  rescue JSON::ParserError, ActiveRecord::RecordInvalid => e
    record_failure(definition, e.message)
  end

  def apply_asset_actions(actions)
    properties = (@asset.properties || {}).deep_dup
    apply_tag_actions(properties, actions)
    properties.merge!(actions["patch_metadata"]) if actions["patch_metadata"].is_a?(Hash)

    attrs = { properties: properties }
    attrs[:status] = actions["set_status"].to_s if actions["set_status"].present?
    @asset.update!(attrs)
  end

  def apply_tag_actions(properties, actions)
    properties["tags"] = Array(actions["set_tags"]).map(&:to_s) if actions.key?("set_tags") && actions["set_tags"].is_a?(Array)
    properties["tags"] = (Array(properties["tags"]) | Array(actions["add_tags"]).map(&:to_s)) if actions["add_tags"].is_a?(Array)
    properties["tags"] = (Array(properties["tags"]) - Array(actions["remove_tags"]).map(&:to_s)) if actions["remove_tags"].is_a?(Array)
  end

  def record_failure(definition, message)
    next_count = definition.failure_count.to_i + 1
    attrs = {
      failure_count: next_count,
      last_error: message.to_s.truncate(2_000),
      last_dispatched_at: Time.current,
    }
    attrs[:status] = "disabled" if next_count >= CustomNodeDefinition::CIRCUIT_BREAKER_THRESHOLD
    definition.update!(attrs)
    Rails.logger.warn("[CustomNodeExecutor] Custom node '#{definition.key}' failed: #{message}")
    nil
  end
end
