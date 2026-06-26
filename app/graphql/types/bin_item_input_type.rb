# frozen_string_literal: true

module Types
  # Input type for specifying a single bin item (asset or folder) by ID and type.
  #
  # Used by {Mutations::BulkRestoreFromBin} and related mutations.
  class BinItemInputType < Types::BaseInputObject
    description "A single Recycle Bin item identified by its database ID and resource type."

    argument :id,   ID,     required: true, description: "Database ID of the asset or folder."
    argument :type, String, required: true, description: 'Resource type: "asset" or "folder".'
  end
end
