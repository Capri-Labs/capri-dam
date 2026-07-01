module Types
  class InboxMessageType < Types::BaseObject
    field :id, ID, null: false
    field :subject, String, null: false
    field :body_html, String, null: true
    field :body_text, String, null: true
    field :message_type, String, null: false
    field :read, Boolean, null: false, method: :read?
    field :starred, Boolean, null: false, method: :starred?
    field :archived, Boolean, null: false, method: :archived?
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :sender, Types::UserType, null: true
    field :snippet, String, null: true

    def snippet
      return nil if object.body_text.blank?

      ActionController::Base.helpers.truncate(object.body_text, length: 150)
    end
  end
end
