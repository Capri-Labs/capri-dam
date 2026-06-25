# GraphQL mutation — update an existing user's profile fields.
#
# SSO-managed users may only have their role/department/group assignments
# changed; name and email fields are owned by the identity provider.
module Mutations
  class UpdateUser < Mutations::BaseMutation
    description "Update a DAM user account (admin only)"

    argument :id,          ID,      required: true
    argument :first_name,  String,  required: false
    argument :last_name,   String,  required: false
    argument :department,  String,  required: false
    argument :role,        String,  required: false
    argument :admin,       Boolean, required: false
    argument :active,      Boolean, required: false
    argument :group_ids,   [ ID ],    required: false

    field :user,   Types::UserType, null: true
    field :errors, [ String ],        null: false

    def resolve(id:, **attrs)
      current = context[:current_user]
      return { user: nil, errors: [ "Unauthorized" ] } unless current&.admin?

      user = User.find_by(id: id)
      return { user: nil, errors: [ "User not found" ] } unless user

      safe = user.sso_managed? ? attrs.except(:first_name, :last_name) : attrs
      safe[:user_group_ids] = safe.delete(:group_ids).map(&:to_i) if safe[:group_ids]

      if user.update(safe.compact)
        { user: user, errors: [] }
      else
        { user: nil, errors: user.errors.full_messages }
      end
    end
  end
end
