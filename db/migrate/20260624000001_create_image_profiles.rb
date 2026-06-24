class CreateImageProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :image_profiles do |t|
      t.string   :name,                    null: false
      t.jsonb    :unsharp_mask,            null: false, default: { 'amount' => 1.75, 'radius' => 0.2, 'threshold' => 2 }
      t.string   :crop_type,               null: false, default: 'none'
      t.jsonb    :responsive_crops,        null: false, default: []
      t.boolean  :responsive_crop_enabled, null: false, default: false
      t.boolean  :swatch_enabled,          null: false, default: false
      t.integer  :swatch_width,                         default: 100
      t.integer  :swatch_height,                        default: 100
      t.datetime :deleted_at

      t.timestamps null: false
    end

    add_index :image_profiles, :name
    add_index :image_profiles, :deleted_at
  end
end

