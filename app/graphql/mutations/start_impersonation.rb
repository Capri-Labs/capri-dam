# GraphQL mutation — start an impersonation session.
#
# Admin/super-admin only.  Applies the same role-hierarchy rules as
# Impersonation::SessionsController.
module Mutations
  class StartImpersonation < Mutations::BaseMutation
    description "Begin impersonating another user (admin/super-admin only)"

    argument :user_id, ID, required: true, description: "ID of the user to impersonate"

    field :success,           Boolean, null: false
    field :message,           String,  null: false
    field :impersonated_user, Types::UserType, null: true

    def resolve(user_id:)
      actor = context[:current_user]
      raise GraphQL::ExecutionError, "Not authenticated" unless actor

      target = User.find_by(id: user_id)
      raise GraphQL::ExecutionError, "User not found" unless target

      unless target.can_be_impersonated_by?(actor)
        raise GraphQL::ExecutionError, "Not authorised to impersonate this user"
      end

      AuditLog.record(
        action:       "impersonation_start",
        auditable:    target,
        user:         actor,
        changes_data: { impersonated_user: target.email, impersonated_by: actor.email },
      )

      context[:session][:impersonated_user_id] = target.id
      context[:session][:impersonator_id]      = actor.id

      { success: true, message: "Impersonating #{target.display_name}", impersonated_user: target }
    end
  end
end
