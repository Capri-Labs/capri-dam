# GraphQL mutation — delete a non-system user group.
module Mutations
  class DeleteUserGroup < Mutations::BaseMutation
    description "Delete a non-system user group (admin only)"

    argument :id, ID, required: true

    field :success, Boolean, null: false
    field :errors,  [ String ], null: false

    def resolve(id:)
      return { success: false, errors: [ "Unauthorized" ] } unless context[:current_user]&.admin?

      group = UserGroup.find_by(id: id)
      return { success: false, errors: [ "Group not found" ] } unless group
      return { success: false, errors: [ "System groups cannot be deleted" ] } if group.system?

      group.destroy
      { success: true, errors: [] }
    end
  end
end
