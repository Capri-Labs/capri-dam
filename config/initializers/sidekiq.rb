# 1. Core Requires
require 'sidekiq'
require 'sidekiq/web'

# 2. Web UI Extensions
# In v2+, requiring this AFTER 'sidekiq/web' automatically hooks into the UI.
# No manual method calls (like enhance_queues_tab!) are needed or supported.
require 'sidekiq/throttled/web'

# 3. Redis Connection Standardization
# This mirrors approach of defining the connection once and passing it to both client/server
redis_config = {
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
  # Add timeouts or namespace configurations here if needed
}

# 4. Server Configuration (The Worker Processes)
Sidekiq.configure_server do |config|
  config.redis = redis_config

  # typically registers custom error handlers here for zero-noise operations
  config.error_handlers << proc do |ex, ctx_hash|
    Rails.logger.error("Sidekiq Error in #{ctx_hash[:job]['class']}: #{ex.message}")
  end
end

# 5. Client Configuration (The Rails Web Processes pushing jobs)
Sidekiq.configure_client do |config|
  config.redis = redis_config
end