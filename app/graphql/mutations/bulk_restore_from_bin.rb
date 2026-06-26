# frozen_string_literal: true

module Mutations
  # Bulk-restore one or more soft-deleted assets and/or folders from the bin.
  #
  # == Arguments
  # * +items+ — array of +{ id: ID!, type: String! }+ hashes
  #
  # == Returns
  # * +restored+ — count of successfully restored items
  # * +errors+   — any per-item failure messages
  class BulkRestoreFromBin < Mutations::BaseMutation
    description "Restore one or more items from the Recycle Bin to their original location."

    argument :items, [ Types::BinItemInputType ], required: true,
             description: "Array of { id, type } objects to restore."

    field :restored, Integer,    null: true
    field :errors,   [ String ], null: false

    def resolve(items:)
      user = context[:current_user]
      return { restored: nil, errors: [ "Authentication required." ] } unless user

      restored = 0
      errors   = []

      items.each do |item|
        id   = item[:id].to_i
        type = item[:type].to_s

        begin
          if type == "folder"
            Folder.trashed.find(id).restore
          else
            Asset.trashed.find(id).restore
          end
          restored += 1
        rescue ActiveRecord::RecordNotFound
          errors << "#{type.capitalize} ##{id} not found in bin."
        end
      end

      { restored: restored, errors: errors }
    rescue StandardError => e
      { restored: nil, errors: [ e.message ] }
    end
  end
end
