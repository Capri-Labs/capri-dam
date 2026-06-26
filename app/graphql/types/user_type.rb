# GraphQL type for a DAM user account.
#
# Exposes the fields needed by the admin UI overlay tabs (Properties, Groups,
# Impersonators, Preferences) and the self-service Profile page.
# Sensitive fields such as encrypted_password and reset_password_token
# are intentionally omitted.
module Types
  class UserType < Types::BaseObject
    description "A DAM user account"

    field :id,           ID,      null: false
    field :email,        String,  null: false
    field :username,     String,  null: true
    field :display_name, String,  null: false
    field :first_name,   String,  null: true
    field :last_name,    String,  null: true
    field :name,         String,  null: false
    field :department,   String,  null: true
    field :role,         String,  null: true
    field :avatar_url,   String,  null: true
    field :admin,        Boolean, null: false
    field :active,       Boolean, null: false
    field :sso_managed,  Boolean, null: false
    field :provider,     String,  null: true
    field :created_at,   GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,   GraphQL::Types::ISO8601DateTime, null: false

    field :groups, [ Types::UserGroupType ], null: false,
          description: "Groups this user belongs to"

    field :impersonators, [ Types::UserType ], null: false,
          description: "Users allowed to impersonate this account"

    field :preferences, Types::UserPreferenceType, null: true,
          description: "Language, theme, timezone and notification preferences"

    field :personal_access_tokens, [ Types::PersonalAccessTokenType ], null: false,
          description: "API tokens owned by this user (only returned for own account)"

    # ── Resolvers ──────────────────────────────────────────────────────────

    def sso_managed
      object.sso_managed?
    end

    def groups
      object.user_groups
    end

    def impersonators
      object.impersonators
    end

    def preferences
      object.preference
    end

    def personal_access_tokens
      # Only expose PATs when the viewer is looking at their own account.
      return [] unless context[:current_user]&.id == object.id ||
                       context[:current_user]&.admin?
      object.personal_access_tokens.order(created_at: :desc)
    end
  end
end
