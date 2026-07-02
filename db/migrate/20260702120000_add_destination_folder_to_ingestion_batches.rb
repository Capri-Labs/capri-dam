# frozen_string_literal: true

# Adds destination_folder_id to ingestion_batches so a migration can target a
# specific DAM folder chosen in the "Select Destination" wizard step. Nullable
# because legacy batches (and API callers that omit it) fall back to an
# auto-generated staging folder at commit time.
class AddDestinationFolderToIngestionBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :ingestion_batches, :destination_folder_id, :uuid, default: nil
    add_index :ingestion_batches, :destination_folder_id
  end
end
