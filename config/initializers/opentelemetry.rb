require 'opentelemetry/sdk'
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'headless-dam-rails'

  # This automatically detects your Jaeger or OTel Collector endpoint
  # If empty, it defaults to localhost:4317
  c.use_all()
end