# GraphQL type representing a user group (including built-in system groups).
#
# System groups (everyone, administrators, super-administrators) are flagged
# via +is_system+ and will surface a +deletable: false+ field so the UI can
# disable destructive actions appropriately.
module Types
  class UserGroupType < Types::BaseObject
    description "A hierarchical group used to manage user permissions"

    field :id,           ID,      null: false
    field :name,         String,  null: false
    field :slug,         String,  null: true
    field :description,  String,  null: true
    field :is_system,    Boolean, null: false
    field :deletable,    Boolean, null: false,
          description: "False for built-in system groups that cannot be deleted"
    field :parent_id,    ID,      null: true
    field :member_count, Integer, null: false
    field :created_at,   GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,   GraphQL::Types::ISO8601DateTime, null: false

    field :members,      [Types::UserType],      null: false, description: "Direct user members"
    field :child_groups, [Types::UserGroupType], null: false, description: "Nested sub-groups"
    field :permissions,  [Types::FolderPolicyType], null: false, description: "ACL entries for this group"

    def deletable
      !object.system?
    end

    def member_count
      object.users.count
    end

    def members
      object.users
    end

    def child_groups
      object.child_groups
    end

    def permissions
      object.folder_policies
    end
  end
end

