class CreateQuarantinedAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :quarantined_assets do |t|
      t.references :system_connector, null: false, foreign_key: true
      t.jsonb :original_payload
      t.text :rejection_reason
      t.string :status

      t.timestamps
    end
  end
end
