# GraphQL type for a {CollectionPolicy} — the collection-scoped analogue of
# {FolderPolicyType}. Read-only: policy CRUD is REST-only (see
# +Api::V1::CollectionsController#policies/#upsert_policy/#remove_policy+),
# matching the existing convention for {FolderPolicyType}.
module Types
  class CollectionPolicyType < Types::BaseObject
    graphql_name "CollectionPolicy"
    description "Access-control entry linking a user group to a collection (viewer/editor/collection-admin tiers)"

    field :id,            ID,      null: false
    field :collection_id, ID,      null: false
    field :group_id,      ID,      null: false, method: :user_group_id
    field :group_name,    String,  null: true

    field :view_access,   Boolean, null: false
    field :edit_access,   Boolean, null: false
    field :admin_access,  Boolean, null: false
    field :explicit_deny, Boolean, null: false

    def group_name = object.user_group&.name
  end
end
