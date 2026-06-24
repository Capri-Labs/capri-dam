# frozen_string_literal: true

class CreateVideoProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :video_profiles do |t|
      t.string   :name,                          null: false
      t.text     :description
      t.boolean  :encode_for_adaptive_streaming, null: false, default: true
      t.jsonb    :smart_crop_ratios,             null: false, default: []
      t.datetime :deleted_at

      t.timestamps null: false
    end

    add_index :video_profiles, :name
    add_index :video_profiles, :deleted_at
  end
end

