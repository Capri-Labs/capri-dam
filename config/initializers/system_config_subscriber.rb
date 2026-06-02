# We only want to start the listener thread inside an actual server process (Puma).
# This prevents the listener from hijacking DB migrations, assets compilation, or tests.
if defined?(Rails::Server) || defined?(Puma)
  Thread.new do
    # Enterprise Resilience: Wrap the subscriber in a permanent crash-recovery loop
    loop do
      begin
        # Establish a dedicated, blocking connection for the subscription stream
        # Using standard Redis configuration parameters matching your project's environment
        redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
        redis = Redis.new(url: redis_url)

        Rails.logger.info("System Sync: Connected to Redis Pub/Sub channel 'system_config_updates'")

        redis.subscribe("system_config_updates") do |on|
          on.message do |channel, msg|
            payload = JSON.parse(msg) rescue {}

            case payload["key"]
            when "global_log_level"
              new_level = payload["value"].to_s.upcase

              # Map the incoming string value to Ruby's Logger constants
              log_constant = case new_level
                             when 'DEBUG' then Logger::DEBUG
                             when 'INFO'  then Logger::INFO
                             when 'WARN'  then Logger::WARN
                             when 'ERROR' then Logger::ERROR
                             when 'FATAL' then Logger::FATAL
                             else Logger::INFO
                             end

              # Thread-safely update the dynamic memory of the active logger instance
              if Rails.logger.level != log_constant
                old_level = Logger::Severity.constants.find { |c| Logger.const_get(c) == Rails.logger.level }
                Rails.logger.level = log_constant

                # Write an explicit lifecycle log showing the runtime adjustment
                Rails.logger.warn("SYSTEM LIFECYCLE: Operational Log Level changed from [#{old_level}] to [#{new_level}] dynamically via Control Plane.")
              end
            end
          end
        end
      rescue => e
        # If the Redis connection drops, suppress the crash, log the error, wait, and retry reconnecting.
        # This keeps the application server alive even if the observability infrastructure blips.
        backtrace = e.backtrace&.first(3)&.join(" | ")
        # Using standard stderr printing because the logger stream might be compromised
        warn "SYSTEM ERROR: Log Subscriber disconnected: #{e.message}. Reconnecting in 5 seconds... TRACE: #{backtrace}"
        sleep 5
      end
    end
  end
end