module Mutations
  class ArchiveInboxMessage < BaseMutation
    argument :id, ID, required: true

    field :success, Boolean, null: false

    def resolve(id:)
      message = context[:current_user]&.inbox_messages&.find_by(id: id)
      raise GraphQL::ExecutionError, "Message not found" unless message

      message.archive!
      { success: true }
    end
  end
end
