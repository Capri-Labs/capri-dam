# frozen_string_literal: true

# lib/tasks/graphql_schema.rake
#
# Dumps the live HeadlessDamSchema SDL to swagger/graphql/schema.graphql so
# SpectaQL can generate static HTML docs without a running server.
#
# Usage:
#   bundle exec rails graphql:schema:dump
#
namespace :graphql do
  namespace :schema do
    desc "Dump the GraphQL SDL schema to swagger/graphql/schema.graphql"
    task dump: :environment do
      output_path = Rails.root.join("swagger/graphql/schema.graphql")
      FileUtils.mkdir_p(File.dirname(output_path))

      schema_sdl = HeadlessDamSchema.to_definition
      File.write(output_path, schema_sdl)

      puts "✓ GraphQL SDL schema written to #{output_path}"
    end
  end
end
