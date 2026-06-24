module Types
  class MutationType < Types::BaseObject
    description "The single mutation register for strict state alterations."

    field :update_asset_metadata, mutation: Mutations::UpdateAssetMetadata

    field :create_collection,           mutation: Mutations::CreateCollection
    field :add_asset_to_collection,     mutation: Mutations::AddAssetToCollection
    field :remove_asset_from_collection, mutation: Mutations::RemoveAssetFromCollection

    # Image Profiles
    field :create_image_profile, mutation: Mutations::CreateImageProfile
    field :update_image_profile, mutation: Mutations::UpdateImageProfile
  end
end