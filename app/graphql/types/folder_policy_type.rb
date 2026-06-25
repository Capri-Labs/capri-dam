# GraphQL type for a folder-level ACL entry.
#
# Exposes the full permission matrix (Read / Modify / Create / Delete /
# Replicate / Manage) plus the explicit-deny flag and inherited flag.
module Types
  class FolderPolicyType < Types::BaseObject
    description "ACL entry linking a user group to a folder with specific permissions"

    field :id,            ID,      null: false
    field :folder_id,     ID,      null: false
    field :group_id,      ID,      null: false, method: :user_group_id
    field :group_name,    String,  null: false
    field :inherited,     Boolean, null: false, description: "True when the rule is inherited from a parent folder"
    field :source_folder, String,  null: true,  description: "Name of the folder where the rule originates"

    # Permission matrix
    field :read,      Boolean, null: false
    field :modify,    Boolean, null: false
    field :create,    Boolean, null: false
    field :delete,    Boolean, null: false
    field :replicate, Boolean, null: false
    field :manage,    Boolean, null: false
    field :explicit_deny, Boolean, null: false

    def group_name  = object.user_group&.name
    def inherited   = false   # REST layer sets this; GraphQL returns raw policy
    def source_folder = nil

    def read      = object.read_access
    def modify    = object.modify_access
    def create    = object.create_access
    def delete    = object.delete_access
    def replicate = object.replicate_access
    def manage    = object.manage_access
    def explicit_deny = object.explicit_deny
  end
end
