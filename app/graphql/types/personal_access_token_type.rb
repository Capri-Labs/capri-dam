# GraphQL type for a Personal Access Token.
#
# The +raw_token+ field is intentionally NOT exposed here — it is only
# returned once via the REST API at creation time.
module Types
  class PersonalAccessTokenType < Types::BaseObject
    description "A personal access token for API / CLI authentication"

    field :id,           ID,      null: false
    field :name,         String,  null: false
    field :scopes,       String,  null: false
    field :last_four,    String,  null: false
    field :active,       Boolean, null: false
    field :last_used_at, GraphQL::Types::ISO8601DateTime, null: true
    field :expires_at,   GraphQL::Types::ISO8601DateTime, null: true
    field :created_at,   GraphQL::Types::ISO8601DateTime, null: false
  end
end
