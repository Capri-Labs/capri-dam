# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# esbuild writes compiled bundles into app/assets/builds/.
# Add it directly to the Propshaft load path so that javascript_include_tag "application"
# and stylesheet_link_tag "application" resolve correctly without a "builds/" prefix.
Rails.application.config.assets.paths << Rails.root.join("app/assets/builds")
