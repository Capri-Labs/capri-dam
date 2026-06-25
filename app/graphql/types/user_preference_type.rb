# GraphQL type for user language and notification preferences.
module Types
  class UserPreferenceType < Types::BaseObject
    description "User-level language and notification preferences"

    field :language,                 String,  null: false
    field :receive_mention_emails,   Boolean, null: false
    field :receive_workflow_emails,  Boolean, null: false
  end
end
