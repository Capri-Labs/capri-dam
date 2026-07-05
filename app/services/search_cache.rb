# frozen_string_literal: true

# Thin, defensive Redis-backed cache used to keep the global search bar and
# +/search+ screen fast under load.
#
# Design goals:
# * Never take down search when Redis is unreachable — any connection error
#   is swallowed and the block is simply executed uncached.
# * Keys are namespaced (`dam:search:*`) so they can be bulk-flushed without
#   touching unrelated cache entries (Sidekiq, RedisTokenManager, etc).
# * Values are JSON-encoded so both plain hashes/arrays and primitives can be
#   stored without marshalling concerns across Ruby versions.
#
# @see RedisTokenManager for the sibling pattern used for vault-style tokens.
class SearchCache
  NAMESPACE = "dam:search"

  # Fetches +key+ from Redis, or computes+stores the block's result.
  #
  # @param key [String] logical cache key (namespaced automatically)
  # @param expires_in [ActiveSupport::Duration, Integer] TTL in seconds
  # @return [Object] the cached (or freshly computed) value
  def self.fetch(key, expires_in: 30)
    # Mirrors `config.cache_store = :null_store` in the test environment —
    # search specs create/mutate fixtures per-example, so caching identical
    # query-param cache keys across examples would leak stale results.
    return yield if Rails.env.test?

    full_key = build_key(key)

    cached = redis.get(full_key)
    return JSON.parse(cached, symbolize_names: true) if cached.present?

    value = yield
    redis.setex(full_key, expires_in.to_i, value.to_json)
    value
  rescue Redis::BaseError, SystemCallError => e
    Rails.logger.warn("[SearchCache] Redis unavailable (#{e.class}); serving uncached. #{e.message}")
    yield
  end

  # Removes every cached search entry. Useful after bulk asset imports.
  def self.flush_all
    cursor = "0"
    loop do
      cursor, keys = redis.scan(cursor, match: "#{NAMESPACE}:*", count: 200)
      redis.del(*keys) if keys.any?
      break if cursor == "0"
    end
  rescue Redis::BaseError, SystemCallError => e
    Rails.logger.warn("[SearchCache] flush_all failed: #{e.message}")
  end

  def self.build_key(key)
    "#{NAMESPACE}:#{key}"
  end

  def self.redis
    @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  end
end
