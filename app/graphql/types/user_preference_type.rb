# GraphQL type for user language, notification preferences and theme.
module Types
  class UserPreferenceType < Types::BaseObject
    description "User-level language, notification preferences and theme"

    field :language,                 String,  null: false
    field :theme,                    String,  null: false
    field :receive_mention_emails,   Boolean, null: false
    field :receive_workflow_emails,  Boolean, null: false
  end
end
