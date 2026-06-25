# GraphQL mutation — create a new user group.
module Mutations
  class CreateUserGroup < Mutations::BaseMutation
    description "Create a new user group (admin only)"

    argument :name,        String, required: true
    argument :description, String, required: false
    argument :parent_id,   ID,     required: false

    field :user_group, Types::UserGroupType, null: true
    field :errors,     [String],             null: false

    def resolve(name:, description: nil, parent_id: nil)
      return { user_group: nil, errors: ["Unauthorized"] } unless context[:current_user]&.admin?

      group = UserGroup.new(name: name, description: description)

      if group.save
        if parent_id.present?
          parent = UserGroup.find_by(id: parent_id)
          parent&.add_child(group)
        end
        { user_group: group, errors: [] }
      else
        { user_group: nil, errors: group.errors.full_messages }
      end
    end
  end
end

