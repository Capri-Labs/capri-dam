module Mutations
  class RemoveAssetFromCollection < BaseMutation
    description "Removes an asset from a collection without deleting the original asset"

    argument :collection_id, ID, required: true
    argument :asset_id, ID, required: true

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(collection_id:, asset_id:)
      collection = Collection.find_by(id: collection_id)
      return { collection: nil, errors: [ "Collection not found" ] } unless collection

      join_record = CollectionAsset.find_by(collection_id: collection_id, asset_id: asset_id)

      if join_record
        join_record.destroy
        { collection: collection.reload, errors: [] }
      else
        { collection: collection, errors: [ "Asset is not in this collection" ] }
      end
    end
  end
end
