source "https://rubygems.org"

gem "dotenv-rails", groups: [ :development, :test ]

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"

# Ruby 4.0 removed several stdlib network libs from default gems — declare them
# explicitly so they are available both locally and in CI.
gem "net-ftp"   # used by ingestion_adapters/ftp_adapter.rb

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # OpenAPI contract testing — validates every API response against swagger.yaml
  gem "committee"

  # Consumer-driven contract testing (PACT) — provider verification
  gem "pact"
  gem "pact-support"

  # Database cleanup strategy between integration tests
  gem "database_cleaner-active_record"

  # HTTP stubbing for PACT consumer tests
  gem "webmock"
end

# Database and Authentication Logic
gem "devise"

gem "responders"

group :development, :test do
  gem "rspec-rails"
  gem "rspec_junit_formatter", require: false # JUnit XML output for CI
  gem "factory_bot_rails"
  gem "faker" # Optional: generates random data for tests

  # Restores `assigns(...)` / `assert_template` helpers in request & controller specs
  gem "rails-controller-testing"

  # Code coverage for the RSpec suite (unit + integration/request specs)
  gem "simplecov", require: false
  gem "simplecov-cobertura", require: false # CI-friendly XML report
end
gem "doorkeeper", "~> 5.9"

gem "sidekiq"
gem "sidekiq-throttled", "~> 2.0"
gem "redis"

# Runtime (production-grade) code coverage for E2E / live traffic.
# Captures which lines actually execute during real requests & E2E flows.
# Scoped away from :test so it doesn't clash with SimpleCov's Coverage hook.
gem "coverband", groups: [ :development, :production ]

# Swagger (OpenAPI) file.
gem "rswag-api"
gem "rswag-ui"
gem "rswag-specs"

# Add the SSO Engine
gem "omniauth-keycloak"
gem "omniauth-rails_csrf_protection" # Crucial for security

gem "aws-sdk-s3", "~> 1"
gem "google-cloud-storage", "~> 1.0"
gem "azure-storage-blob", "~> 2.0"
gem "liquid", "~> 5.12"

gem "mini_magick", "~> 5.3"

gem "marcel", "~> 1.1"

# CSV generation (removed from Ruby's default gems in 3.4+)
gem "csv"

gem "prawn"
gem "prawn-table"

gem "caxlsx"

gem "graphql"
gem "graphiql-rails", group: :development


group :production, :development do
  gem "opentelemetry-instrumentation-all"
  gem "opentelemetry-instrumentation-rails"
  gem "opentelemetry-instrumentation-http"
  gem "opentelemetry-exporter-otlp" # For sending data to an OTel collector
end

# Vector database support for PostgreSQL pgvector
gem "neighbor"

gem "rtesseract", "~> 3.1"

# ── Security: explicit version floors for CVE fixes ──────────────────────────
# faraday CVE-2026-25765 (SSRF) → >= 1.10.5 (1.x branch fix, constrained by azure-storage-blob)
# faraday CVE-2026-54297 (DoS)  → needs >= 2.14.3, but azure-storage-blob pins faraday ~> 1.0
#   → accepted / ignored in config/bundler-audit.yml until azure-storage-blob is upgraded
gem "faraday", "~> 1.10", ">= 1.10.6"
# jwt      CVE-2026-45363 (empty-key HMAC bypass)         → >= 3.2.0
gem "jwt", ">= 3.2.0"
# net-imap CVE-2026-42245 (quadratic complexity DoS)      → >= 0.6.4
gem "net-imap", ">= 0.6.4"
# nokogiri CVEs (Use-After-Free, invalid memory read)     → >= 1.19.4
gem "nokogiri", ">= 1.19.4"
# oauth2   GHSA-pp92-crg2-gfv9 (protocol-relative SSRF)  → >= 2.0.22
gem "oauth2", ">= 2.0.22"

gem "akamai-edgegrid"
