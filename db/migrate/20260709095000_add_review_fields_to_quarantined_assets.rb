class AddReviewFieldsToQuarantinedAssets < ActiveRecord::Migration[8.1]
  def up
    add_column :quarantined_assets, :asset_id, :uuid unless column_exists?(:quarantined_assets, :asset_id)
    add_index :quarantined_assets, :asset_id unless index_exists?(:quarantined_assets, :asset_id)
    add_foreign_key :quarantined_assets, :assets, column: :asset_id unless foreign_key_exists?(:quarantined_assets, :assets, column: :asset_id)

    unless column_exists?(:quarantined_assets, :reviewed_by_id)
      add_reference :quarantined_assets, :reviewed_by, null: true, foreign_key: { to_table: :users }
    end

    add_column :quarantined_assets, :reviewed_at, :datetime unless column_exists?(:quarantined_assets, :reviewed_at)
    add_column :quarantined_assets, :review_notes, :text unless column_exists?(:quarantined_assets, :review_notes)
  end

  def down
    remove_column :quarantined_assets, :review_notes if column_exists?(:quarantined_assets, :review_notes)
    remove_column :quarantined_assets, :reviewed_at if column_exists?(:quarantined_assets, :reviewed_at)

    if column_exists?(:quarantined_assets, :reviewed_by_id)
      remove_foreign_key :quarantined_assets, column: :reviewed_by_id if foreign_key_exists?(:quarantined_assets, column: :reviewed_by_id)
      remove_index :quarantined_assets, :reviewed_by_id if index_exists?(:quarantined_assets, :reviewed_by_id)
      remove_column :quarantined_assets, :reviewed_by_id
    end

    if column_exists?(:quarantined_assets, :asset_id)
      remove_foreign_key :quarantined_assets, column: :asset_id if foreign_key_exists?(:quarantined_assets, column: :asset_id)
      remove_index :quarantined_assets, :asset_id if index_exists?(:quarantined_assets, :asset_id)
      remove_column :quarantined_assets, :asset_id
    end
  end
end
