require_relative "boot"

require "rails/all"

require_relative "../lib/structured_json_formatter"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module HeadlessDam
  class Application < Rails::Application
    config.active_record.query_log_tags_enabled = true
    config.active_record.query_log_tags = [
      # Rails query log tags:
      :application, :controller, :action, :job,
      # GraphQL-Ruby query log tags:
      current_graphql_operation: -> { GraphQL::Current.operation_name },
      current_graphql_field: -> { GraphQL::Current.field&.path },
      current_dataloader_source: -> { GraphQL::Current.dataloader_source_class }
    ]
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Dump the schema as SQL (db/structure.sql) instead of Ruby (db/schema.rb).
    #
    # Some migrations define raw SQL objects (e.g. the `protect_audit_logs`
    # trigger/function added in 20260527142102_add_immutability_to_audit_logs)
    # that db/schema.rb cannot represent. With the Ruby schema format, any
    # database rebuilt via `db:schema:load` / `db:prepare` / `db:test:prepare`
    # (fresh dev setups, CI, `make dev`) would silently be missing that
    # trigger even though the migration is recorded as applied — defeating
    # the audit log's immutability guarantee. `:sql` captures the full
    # structure, including triggers and functions, so it round-trips exactly.
    config.active_record.schema_format = :sql

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.active_job.queue_adapter = :sidekiq

    # Override the global log formatter
    config.log_formatter = StructuredJsonFormatter.new

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Force ActiveStorage to use ImageMagick instead of Vips
    config.active_storage.variant_processor = :mini_magick
  end
end
