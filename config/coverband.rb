# frozen_string_literal: true
#
# Coverband configuration — runtime / E2E code coverage.
#
# Unlike SimpleCov (which measures coverage during the RSpec suite), Coverband
# records which application lines actually execute while the app serves *real*
# traffic. Point your backend E2E tests (Capybara system specs, Playwright, or
# manual click-throughs) at a running server and Coverband captures the
# exercised code paths into Redis.
#
# View the report at: /admin/coverband  (mounted in config/routes.rb, admin-only)
#
# This file is auto-loaded by the Coverband railtie. The gem is only bundled in
# :development and :production, so it never runs under :test.

require "coverband" if defined?(Coverband).nil?

Coverband.configure do |config|
  redis_url = ENV.fetch("COVERBAND_REDIS_URL", ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))

  store =
    begin
      # Probe the connection eagerly (Redis.new is lazy) so we can fall back
      # cleanly when Redis is unavailable instead of crashing later.
      redis = Redis.new(url: redis_url)
      redis.ping
      Coverband::Adapters::RedisStore.new(redis, redis_namespace: "coverband_e2e")
    rescue StandardError => e
      warn "[Coverband] Redis unavailable (#{e.message}); using file store fallback."
      Coverband::Adapters::FileStore.new(Rails.root.join("tmp", "coverband_e2e.json").to_s)
    end

  config.store = store

  # Track ERB/HAML view usage in addition to Ruby files.
  config.track_views = true

  # Push collected data to the store every N seconds in a background thread.
  config.background_reporting_sleep_seconds = 15

  # Ignore framework/boilerplate paths we don't author.
  config.ignore += %w[
    app/channels/*
    config/*
    db/*
    spec/*
    test/*
    vendor/*
    bin/*
  ]
end

