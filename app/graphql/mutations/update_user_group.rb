# GraphQL mutation — update a user group's name or description.
#
# System groups have additional protection:
# * +everyone+ — immutable; no changes allowed.
# * +administrators+ — only super-admins can modify.
# * +super-administrators+ — only super-admins can modify.
module Mutations
  class UpdateUserGroup < Mutations::BaseMutation
    description "Update a user group (admin only)"

    argument :id,          ID,     required: true
    argument :name,        String, required: false
    argument :description, String, required: false

    field :user_group, Types::UserGroupType, null: true
    field :errors,     [String],             null: false

    def resolve(id:, **attrs)
      current = context[:current_user]
      return { user_group: nil, errors: ["Unauthorized"] } unless current&.admin?

      group = UserGroup.find_by(id: id)
      return { user_group: nil, errors: ["Group not found"] } unless group

      if group.administrators? && !current.super_admin?
        return { user_group: nil, errors: ["Only super-administrators can modify this group"] }
      end

      if group.update(attrs.compact)
        { user_group: group, errors: [] }
      else
        { user_group: nil, errors: group.errors.full_messages }
      end
    end
  end
end

