module CdnAdapters
  # No-op CDN adapter used whenever neither the database (+CdnConfiguration+)
  # nor +config/cdn_settings.yml+ define an active provider for the current
  # environment (e.g. local development/CI, where `cdn_settings.yml` only
  # ships a `production:` section). Keeps CDN invalidation workers from
  # raising and crashing background jobs when no CDN is configured.
  class NullAdapter < BaseAdapter
    def initialize(credentials = {})
      super
    end

    def purge_tag(tag, soft_purge: true)
      Rails.logger.info("[CdnAdapters::NullAdapter] Skipping purge_tag(#{tag.inspect}) — no CDN configured.")
      { skipped: true, reason: "no_cdn_configured" }
    end

    def purge_batch(tags, soft_purge: true)
      Rails.logger.info("[CdnAdapters::NullAdapter] Skipping purge_batch(#{tags.inspect}) — no CDN configured.")
      { skipped: true, reason: "no_cdn_configured" }
    end

    def sync_metadata(uuid, json_payload)
      Rails.logger.info("[CdnAdapters::NullAdapter] Skipping sync_metadata(#{uuid.inspect}) — no CDN configured.")
      { skipped: true, reason: "no_cdn_configured" }
    end
  end
end
