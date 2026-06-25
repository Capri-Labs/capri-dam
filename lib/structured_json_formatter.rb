# Custom +Logger::Formatter+ that emits every log entry as a single JSON line.
#
# Designed for structured logging pipelines (Datadog, Elasticsearch, Splunk,
# etc.) where each log event must be machine-parseable.  Attach it to the Rails
# logger via an initializer:
#
#   Rails.logger.formatter = StructuredJsonFormatter.new
#
# == Output shape
#
#   {
#     "timestamp": "2026-06-24T12:34:56.789Z",
#     "level":     "INFO",
#     "message":   "Started GET / for 127.0.0.1",
#     "environment": "production",
#     "trace_id":  "abc123",   // only present when OpenTelemetry is active
#     "span_id":   "def456"    // only present when OpenTelemetry is active
#   }
#
# == OpenTelemetry integration
#
# When the +opentelemetry-sdk+ gem is loaded and an active span exists, the
# formatter automatically injects +trace_id+ and +span_id+ into every log line
# so that logs can be correlated with distributed traces without any extra
# middleware.
#
# @see https://opentelemetry.io/docs/instrumentation/ruby/
require "json"

class StructuredJsonFormatter < ::Logger::Formatter
  # Formats a log event as a JSON string (with a trailing newline).
  #
  # @param severity [String]  log level label (e.g. +"INFO"+, +"ERROR"+)
  # @param time     [Time]    the timestamp of the log event
  # @param progname [String, nil] optional program name (unused)
  # @param msg      [String, Exception, Object] the log message
  # @return [String] a single JSON line terminated with +\n+
  def call(severity, time, progname, msg)
    payload = {
      timestamp:   time.utc.iso8601(3),
      level:       severity,
      message:     format_message(msg),
      environment: Rails.env,
    }

    # Append distributed tracing context when an active span is present.
    if defined?(OpenTelemetry)
      current_span = OpenTelemetry::Trace.current_span
      if current_span.context.valid?
        payload[:trace_id] = current_span.context.hex_trace_id
        payload[:span_id]  = current_span.context.hex_span_id
      end
    end

    "#{payload.to_json}\n"
  end

  private

  # Converts the raw log message to a plain string.
  #
  # * Strings are passed through unchanged.
  # * Exceptions are rendered as +"message (ClassName)\nbacktrace…"+.
  # * Any other object is serialised with +#inspect+.
  #
  # @param msg [String, Exception, Object]
  # @return [String]
  def format_message(msg)
    case msg
    when String    then msg
    when Exception then "#{msg.message} (#{msg.class})\n#{msg.backtrace&.join("\n")}"
    else                msg.inspect
    end
  end
end
