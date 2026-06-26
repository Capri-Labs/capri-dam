# GraphQL mutation — end an active impersonation session.
module Mutations
  class StopImpersonation < Mutations::BaseMutation
    description "End the current impersonation session"

    field :success, Boolean, null: false
    field :message, String,  null: false

    def resolve
      session = context[:session]
      actor   = context[:true_user] || context[:current_user]

      if (imp_id = session&.fetch(:impersonated_user_id, nil))
        impersonated = User.find_by(id: imp_id)
        AuditLog.record(
          action:       "impersonation_end",
          auditable:    impersonated || actor,
          user:         actor,
          changes_data: { impersonated_user: impersonated&.email },
        )
      end

      session&.delete(:impersonated_user_id)
      session&.delete(:impersonator_id)

      { success: true, message: "Impersonation session ended." }
    end
  end
end
