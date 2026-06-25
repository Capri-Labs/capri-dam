# Skip OpenTelemetry in the test environment.
#
# When CI=true, config/environments/test.rb sets config.eager_load=true, which
# causes Zeitwerk to freeze its internal dirs array early in the boot sequence.
# opentelemetry-instrumentation-rails (loaded via c.use_all) then tries to
# register additional Zeitwerk paths *after* they are frozen, producing:
#
#   FrozenError: can't modify frozen Array: [app/controllers, app/models, ...]
#
# OTel tracing is not useful during automated tests anyway, so we guard here.
return if Rails.env.test?

require "opentelemetry/sdk"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = "headless-dam-rails"

  # This automatically detects your Jaeger or OTel Collector endpoint
  # If empty, it defaults to localhost:4317
  c.use_all()
end
