# frozen_string_literal: true

class CreateVideoProfileFolderAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :video_profile_folder_assignments do |t|
      t.references :video_profile, null: false, foreign_key: true
      # folder_id is a UUID – no FK constraint because folders use a UUID PK
      t.uuid :folder_id, null: false

      t.timestamps null: false
    end

    add_index :video_profile_folder_assignments, :folder_id
    add_index :video_profile_folder_assignments,
              [:video_profile_id, :folder_id],
              unique: true,
              name:   'idx_video_profile_folder_assignments_unique'
  end
end

