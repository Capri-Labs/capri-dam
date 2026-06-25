class SystemConfiguration < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true
  validates :data_type, inclusion: { in: %w[string integer boolean json] }

  # Automatically broadcast changes to the Puma workers after a successful save
  after_commit :broadcast_configuration_change, on: [ :create, :update ]

  # Helper method to get a config value, fully type-casted
  def self.get(key_name, default: nil)
    config = find_by(key: key_name)
    return default unless config

    # Check if the TTL has expired
    if config.expires_at.present? && config.expires_at < Time.current
      # If expired, return the fallback and silently update the DB in the background
      config.revert_to_fallback!
      return config.cast_value(config.fallback_value)
    end

    config.cast_value(config.value)
  end

  # Helper method to handle dynamic typing
  def cast_value(val)
    case data_type
    when "integer" then val.to_i
    when "boolean" then ActiveRecord::Type::Boolean.new.cast(val)
    when "json"    then JSON.parse(val) rescue {}
    else val
    end
  end

  def revert_to_fallback!
    update_columns(value: fallback_value, expires_at: nil)
  end

  private

  def broadcast_configuration_change
    # Build a standardized payload
    payload = {
      key: key,
      value: cast_value(value),
      updated_at: updated_at.iso8601,
    }.to_json

    # Publish the event to the Redis cluster
    # Rails 8 uses the redis-client or kredis gems under the hood,
    # but we can access the connection directly through standard Redis configurations.
    Sidekiq.redis { |conn| conn.publish("system_config_updates", payload) } rescue nil
    # Note: If you aren't using Sidekiq, you can substitute this with Kredis.redis.publish or Redis.new.publish
  end
end
