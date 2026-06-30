module Mutations
  class UpdateAssetMetadata < BaseMutation
    description "Safely patches the inner JSONB structural properties map without zeroing unmentioned keys."

    argument :uuid, String, required: true
    argument :updates, Types::JsonType, required: true

    field :asset, Types::AssetType, null: true
    field :errors, [ String ], null: false

    def resolve(uuid:, updates:)
      # Security Check: Ensure mutation account has administrative or manager status
      unless context[:current_user].role?(:manager)
        return { asset: nil, errors: [ "Unauthorized operational modification attempt." ] }
      end

      # When called via HTTP, `updates` may arrive as ActionController::Parameters.
      # Convert to a plain Hash so JSONB merging works correctly.
      safe_updates = updates.respond_to?(:to_unsafe_h) ? updates.to_unsafe_h : updates.to_h

      asset = Asset.find_by(uuid: uuid)
      if asset
        # Merges new updates safely into the existing JSONB hash
        existing_properties = asset.properties || {}
        asset.update!(properties: existing_properties.merge(safe_updates))
        { asset: asset, errors: [] }
      else
        { asset: nil, errors: [ "Target asset structural signature not found." ] }
      end
    end
  end
end
