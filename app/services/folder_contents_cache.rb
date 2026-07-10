# frozen_string_literal: true

# Thin, defensive Redis-backed cache for the folder-contents payload
# (`GET /api/v1/folders/:id`), keyed by folder id + sort/direction.
#
# == Why this exists
#
# Folders with 1,000-3,000+ assets were slow to open: {FoldersController#show}
# eagerly loads every active asset in the folder, formats each one (URL
# resolution, merged properties, etc.), then sorts the whole array in Ruby —
# repeating all of that work on every click, even when nothing in the folder
# changed since the last request.
#
# This mirrors the existing {SearchCache} pattern used by
# +Api::V1::SearchController+:
# * Never take down folder browsing when Redis is unreachable — any
#   connection error is swallowed and the block is simply executed uncached.
# * Keys are namespaced (`dam:folder_contents:*`) so they can be bulk-flushed
#   without touching unrelated cache entries (Sidekiq, SearchCache, etc).
# * Values are JSON-encoded.
#
# == Invalidation strategy
#
# Folder contents are cached with a short TTL ({DEFAULT_TTL}) *and* actively
# busted from the controllers whenever a mutation touches assets/folders that
# would change the payload (upload, delete/restore, rename, move, metadata
# update — see call sites of {.bust}). This gives near-real-time consistency
# for the user who just made the change, while the short TTL is a safety net
# for any mutation path that isn't (or can't be) instrumented (e.g. a
# long-running background worker that changes asset status).
#
# @see SearchCache for the sibling pattern used for the global search index.
class FolderContentsCache
  NAMESPACE = "dam:folder_contents"

  # Cache entries expire on their own after this many seconds even if a
  # mutation is somehow missed by {.bust} — keeps staleness bounded.
  DEFAULT_TTL = 30

  # Fetches the cached payload for +folder_id+ + query params, or computes
  # and stores the block's result.
  #
  # @param folder_id [String, nil] Folder UUID, or +nil+/"root" for the
  #   top-level listing.
  # @param params [Hash] the sort/direction (or any other) params that affect
  #   the payload shape — included in the cache key so distinct
  #   sort/direction combinations never collide.
  # @param expires_in [Integer] TTL in seconds
  # @return [Object] the cached (or freshly computed) value
  def self.fetch(folder_id, params: {}, expires_in: DEFAULT_TTL)
    # Mirrors `config.cache_store = :null_store` in test — specs create/mutate
    # fixtures per-example, so caching identical keys across examples would
    # leak stale results.
    return yield if Rails.env.test?

    key = build_key(folder_id, params)

    cached = redis.get(key)
    return JSON.parse(cached, symbolize_names: true) if cached.present?

    value = yield
    redis.setex(key, expires_in.to_i, value.to_json)
    value
  rescue Redis::BaseError, SystemCallError => e
    Rails.logger.warn("[FolderContentsCache] Redis unavailable (#{e.class}); serving uncached. #{e.message}")
    yield
  end

  # Invalidates every cached listing for +folder_id+ (all sort/direction
  # variants), so the next request recomputes fresh data.
  #
  # Call this from any controller action that mutates an asset or folder
  # (upload, delete, restore, rename, move, metadata update, schema apply…).
  #
  # @param folder_id [String, nil, Array<String, nil>] one or more folder ids
  #   whose cached listings should be busted. +nil+ (or +"root"+) busts the
  #   top-level listing.
  # @return [void]
  def self.bust(folder_id)
    # NOTE: plain `Array(folder_id)` collapses `nil` to `[]` (Ruby's Kernel#Array
    # treats nil as "no elements"), which silently made every top-level
    # (root) mutation a no-op here — the root listing cache would then serve
    # stale data for up to DEFAULT_TTL seconds after any root-level
    # create/rename/delete/restore. Wrap explicitly so a bare `nil` (or a
    # single non-array id) still busts exactly that one key namespace.
    ids = folder_id.is_a?(Array) ? folder_id : [ folder_id ]
    ids.uniq.each do |id|
      cursor = "0"
      pattern = "#{NAMESPACE}:#{normalise_id(id)}:*"
      loop do
        cursor, keys = redis.scan(cursor, match: pattern, count: 200)
        redis.del(*keys) if keys.any?
        break if cursor == "0"
      end
    end
  rescue Redis::BaseError, SystemCallError => e
    Rails.logger.warn("[FolderContentsCache] bust failed: #{e.message}")
  end

  # Removes every cached folder-contents entry. Useful after bulk imports or
  # migrations that touch many folders at once.
  def self.flush_all
    cursor = "0"
    loop do
      cursor, keys = redis.scan(cursor, match: "#{NAMESPACE}:*", count: 200)
      redis.del(*keys) if keys.any?
      break if cursor == "0"
    end
  rescue Redis::BaseError, SystemCallError => e
    Rails.logger.warn("[FolderContentsCache] flush_all failed: #{e.message}")
  end

  def self.build_key(folder_id, params)
    normalized_params = params.to_a.sort.to_h.to_query
    "#{NAMESPACE}:#{normalise_id(folder_id)}:#{Digest::SHA256.hexdigest(normalized_params)}"
  end

  def self.normalise_id(folder_id)
    folder_id.nil? || folder_id == "root" ? "root" : folder_id.to_s
  end

  def self.redis
    @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  end
end
