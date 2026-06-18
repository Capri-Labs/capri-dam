class RedisTokenManager
  # 🚀 Enterprise Taxonomy: dam:vault:{domain}:{service_id}
  # domains: 'cdn', 'webhook', 'third_party_api', 'storage'

  def self.fetch(domain, service_id, expires_in: 1.hour)
    cache_key = build_key(domain, service_id)

    # Rails.cache automatically handles the Redis TTL
    Rails.cache.fetch(cache_key, expires_in: expires_in) do
      Rails.logger.info "🔄 Vault Miss: Generating new #{domain} token for #{service_id}..."

      new_token = yield

      raise "Vault Error: Failed to generate #{domain} token for #{service_id}" if new_token.blank?

      new_token
    end
  end

  # Revoke a single specific token
  def self.revoke(domain, service_id)
    cache_key = build_key(domain, service_id)
    Rails.cache.delete(cache_key)
    Rails.logger.info "🗑️ Vault: Revoked #{domain} token for #{service_id}."
  end

  # 🚀 ADVANCED: Emergency clearing of an entire domain (e.g., all webhooks)
  # Requires direct Redis access, bypassing the standard Rails.cache wrapper
  def self.revoke_domain(domain)
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))

    # SCAN is operationally safe and won't block the Redis main thread
    cursor = "0"
    loop do
      cursor, keys = redis.scan(cursor, match: "dam:vault:#{domain}:*", count: 100)
      redis.del(*keys) if keys.any?
      break if cursor == "0"
    end

    Rails.logger.warn "🚨 Vault: Emergency revocation complete for domain [#{domain}]."
  end

  private

  def self.build_key(domain, service_id)
    "dam:vault:#{domain}:#{service_id}"
  end
end