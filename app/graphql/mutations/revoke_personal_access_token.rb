# GraphQL mutation — revoke a Personal Access Token.
module Mutations
  class RevokePersonalAccessToken < Mutations::BaseMutation
    description "Revoke a Personal Access Token owned by the current user"

    argument :id, ID, required: true

    field :success, Boolean, null: false
    field :message, String,  null: false

    def resolve(id:)
      user = context[:current_user]
      raise GraphQL::ExecutionError, "Not authenticated" unless user

      pat = user.personal_access_tokens.find_by(id: id)
      raise GraphQL::ExecutionError, "Token not found" unless pat

      pat.revoke!

      AuditLog.record(
        action:       "pat_revoked",
        auditable:    pat,
        changes_data: { name: pat.name },
      )

      { success: true, message: "Token '#{pat.name}' has been revoked." }
    end
  end
end
