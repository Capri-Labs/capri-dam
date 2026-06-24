class CreateImageProfileFolderAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :image_profile_folder_assignments do |t|
      t.bigint :image_profile_id, null: false
      t.uuid   :folder_id,        null: false

      t.timestamps null: false
    end

    add_index :image_profile_folder_assignments, :image_profile_id
    add_index :image_profile_folder_assignments, :folder_id
    add_index :image_profile_folder_assignments,
              [:image_profile_id, :folder_id],
              unique: true,
              name: 'idx_image_profile_folder_assignments_unique'

    add_foreign_key :image_profile_folder_assignments, :image_profiles
  end
end

