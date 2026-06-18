class CreateCdnConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :cdn_configurations do |t|
      t.string :provider
      t.boolean :is_active
      t.text :settings

      t.timestamps
    end
  end
end
