# GraphQL type for user language, notification preferences, theme, and timezone.
module Types
  class UserPreferenceType < Types::BaseObject
    description "User-level language, notification preferences, theme and timezone"

    field :language,                 String,  null: false
    field :theme,                    String,  null: false
    field :timezone,                 String,  null: false
    field :receive_mention_emails,   Boolean, null: false
    field :receive_workflow_emails,  Boolean, null: false
  end
end
