class CreateTransformationPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :transformation_presets do |t|
      t.string :name
      t.jsonb :params
      t.string :slug

      t.timestamps
    end
    add_index :transformation_presets, :slug
  end
end
