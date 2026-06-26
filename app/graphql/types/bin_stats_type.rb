# frozen_string_literal: true

module Types
  # GraphQL object type for Recycle Bin aggregate statistics.
  class BinStatsType < Types::BaseObject
    description "Aggregate statistics for the Recycle Bin."

    field :total_items,        Integer,  null: false, description: "Total number of items in the bin."
    field :total_assets,       Integer,  null: false, description: "Number of trashed assets."
    field :total_folders,      Integer,  null: false, description: "Number of trashed folders."
    field :total_size_bytes,   Integer,  null: false, description: "Sum of all trashed asset sizes in bytes."
    field :retention_days,     Integer,  null: false, description: "Items are auto-purged after this many days."
    field :oldest_deleted_at,  GraphQL::Types::ISO8601DateTime, null: true,
          description: "Timestamp of the oldest item currently in the bin."
  end
end
