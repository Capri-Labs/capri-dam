module AssetUrlHelper
  extend ActiveSupport::Concern

  included do
    include Rails.application.routes.url_helpers
  end

  def asset_url_for(asset)
    active_v = asset.active_version
    storage_path = active_v&.properties&.fetch('storage_path', nil) || asset.properties['storage_path']

    return nil unless storage_path.present?

    if Rails.env.production?
      "https://cdn.yourdam.com/assets/#{asset.uuid}"
    else
      # We use our custom local serving route for development
      "/api/v1/assets/local/#{asset.uuid}"
    end
  end
end