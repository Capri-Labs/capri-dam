require 'json'

class StructuredJsonFormatter < ::Logger::Formatter
  def call(severity, time, progname, msg)
    payload = {
      timestamp: time.utc.iso8601(3),
      level: severity,
      message: format_message(msg),
      environment: Rails.env
    }

    # Automatically append distributed tracing context if active
    if defined?(OpenTelemetry)
      current_span = OpenTelemetry::Trace.current_span
      if current_span.context.valid?
        payload[:trace_id] = current_span.context.hex_trace_id
        payload[:span_id] = current_span.context.hex_span_id
      end
    end

    "#{payload.to_json}\n"
  end

  private

  def format_message(msg)
    case msg
    when String then msg
    when Exception then "#{msg.message} (#{msg.class})\n#{msg.backtrace&.join("\n")}"
    else msg.inspect
    end
  end
end