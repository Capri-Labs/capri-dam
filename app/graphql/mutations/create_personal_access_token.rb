# GraphQL mutation — create a Personal Access Token.
#
# The raw token is returned ONCE in the +raw_token+ field and never stored.
module Mutations
  class CreatePersonalAccessToken < Mutations::BaseMutation
    description "Generate a new Personal Access Token for the current user"

    argument :name,       String,  required: true
    argument :scopes,     String,  required: false, default_value: "read"
    argument :expires_at, String,  required: false

    field :success,    Boolean,                     null: false
    field :raw_token,  String,                      null: true,
          description: "The one-time plaintext token. Copy it now."
    field :token,      Types::PersonalAccessTokenType, null: true
    field :errors,     [ String ],                  null: false

    def resolve(name:, scopes: "read", expires_at: nil)
      user = context[:current_user]
      raise GraphQL::ExecutionError, "Not authenticated" unless user

      parsed_expires = expires_at ? Time.zone.parse(expires_at) : nil
      pat, raw = PersonalAccessToken.generate_for(user, name: name, scopes: scopes, expires_at: parsed_expires)

      AuditLog.record(
        action:       "pat_created",
        auditable:    pat,
        changes_data: { name: pat.name, scopes: pat.scopes },
      )

      { success: true, raw_token: raw, token: pat, errors: [] }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, raw_token: nil, token: nil, errors: e.record.errors.full_messages }
    end
  end
end
