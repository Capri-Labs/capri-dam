module Mutations
  class AddAssetToCollection < BaseMutation
    description "Links an existing asset to a collection"

    argument :collection_id, ID, required: true
    argument :asset_id, ID, required: true # This will accept the UUID from the frontend

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(collection_id:, asset_id:)
      collection = Collection.find_by(id: collection_id)
      return { collection: nil, errors: [ "Collection not found" ] } unless collection

      asset = Asset.find_by(id: asset_id)
      return { collection: nil, errors: [ "Asset not found" ] } unless asset

      join_record = CollectionAsset.new(collection: collection, asset: asset)

      if join_record.save
        { collection: collection.reload, errors: [] }
      else
        { collection: nil, errors: join_record.errors.full_messages }
      end
    end
  end
end
