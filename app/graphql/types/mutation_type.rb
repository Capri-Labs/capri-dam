module Types
  class MutationType < Types::BaseObject
    description "The single mutation register for strict state alterations."

    field :update_asset_metadata, mutation: Mutations::UpdateAssetMetadata
    field :publish_asset,         mutation: Mutations::PublishAsset

    field :create_collection,            mutation: Mutations::CreateCollection
    field :add_asset_to_collection,      mutation: Mutations::AddAssetToCollection
    field :remove_asset_from_collection, mutation: Mutations::RemoveAssetFromCollection
    field :configure_collection_rule,    mutation: Mutations::ConfigureCollectionRule

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

    # Impersonation
    field :start_impersonation, mutation: Mutations::StartImpersonation
    field :stop_impersonation,  mutation: Mutations::StopImpersonation

    field :mark_inbox_message_read, mutation: Mutations::MarkInboxMessageRead
    field :archive_inbox_message, mutation: Mutations::ArchiveInboxMessage

    # Personal Access Tokens
    field :create_personal_access_token, mutation: Mutations::CreatePersonalAccessToken
    field :revoke_personal_access_token, mutation: Mutations::RevokePersonalAccessToken

    # Duplicate Manager
    field :resolve_duplicate_group, mutation: Mutations::ResolveDuplicateGroup
    field :trigger_duplicate_scan,  mutation: Mutations::TriggerDuplicateScan

    # Recycle Bin
    field :bulk_restore_from_bin,       mutation: Mutations::BulkRestoreFromBin
    field :empty_bin,                   mutation: Mutations::EmptyBin
    field :update_bin_retention_policy, mutation: Mutations::UpdateBinRetentionPolicy
    field :trigger_bin_purge,           mutation: Mutations::TriggerBinPurge

    # Style & Model Hub (admin only)
    field :create_ai_model_config, mutation: Mutations::CreateAiModelConfig
    field :update_ai_model_config, mutation: Mutations::UpdateAiModelConfig
    field :create_style_preset,    mutation: Mutations::CreateStylePreset
    field :update_style_preset,    mutation: Mutations::UpdateStylePreset
  end
end
