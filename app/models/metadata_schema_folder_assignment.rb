class MetadataSchemaFolderAssignment < ApplicationRecord
  belongs_to :metadata_schema
  # folder_id is a UUID string referencing the folders table
  # We use a plain string rather than belongs_to so we don't need a strict FK
  # (folders use uuid primary keys while this table uses the UUID string directly)

  validates :metadata_schema_id, presence: true
  validates :folder_id,          presence: true
  validates :folder_id,          uniqueness: { scope: :metadata_schema_id }
end

