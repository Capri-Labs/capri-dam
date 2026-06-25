module Types
  class MutationType < Types::BaseObject
    description "The single mutation register for strict state alterations."

    field :update_asset_metadata, mutation: Mutations::UpdateAssetMetadata

    field :create_collection,            mutation: Mutations::CreateCollection
    field :add_asset_to_collection,      mutation: Mutations::AddAssetToCollection
    field :remove_asset_from_collection, mutation: Mutations::RemoveAssetFromCollection

    # Image Profiles
    field :create_image_profile, mutation: Mutations::CreateImageProfile
    field :update_image_profile, mutation: Mutations::UpdateImageProfile

    # Video Profiles
    field :create_video_profile, mutation: Mutations::CreateVideoProfile
    field :update_video_profile, mutation: Mutations::UpdateVideoProfile

    # Users (admin only)
    field :create_user, mutation: Mutations::CreateUser
    field :update_user, mutation: Mutations::UpdateUser

    # User Groups (admin only)
    field :create_user_group, mutation: Mutations::CreateUserGroup
    field :update_user_group, mutation: Mutations::UpdateUserGroup
    field :delete_user_group, mutation: Mutations::DeleteUserGroup
  end
end
