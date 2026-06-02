module Mutations
  class CreateCollection < BaseMutation
    description "Creates a new empty collection"

    argument :name, String, required: true
    argument :description, String, required: false

    field :collection, Types::CollectionType, null: true
    field :errors, [String], null: false

    def resolve(name:, description: nil)
      collection = Collection.new(
        name: name,
        description: description
      # user: context[:current_user] # Uncomment when authentication context is ready
      )

      if collection.save
        { collection: collection, errors: [] }
      else
        { collection: nil, errors: collection.errors.full_messages }
      end
    end
  end
end