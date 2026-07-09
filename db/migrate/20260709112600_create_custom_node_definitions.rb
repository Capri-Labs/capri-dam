class CreateCustomNodeDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_node_definitions do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.string :icon
      t.string :category, null: false, default: "custom"
      t.string :color, null: false, default: "#6366f1"
      t.jsonb :config_schema, null: false, default: []
      t.jsonb :runtime, null: false, default: {}
      t.string :status, null: false, default: "draft"
      t.integer :failure_count, null: false, default: 0
      t.text :last_error
      t.datetime :last_dispatched_at
      t.references :created_by, foreign_key: { to_table: :users }, index: true

      t.timestamps
    end

    add_index :custom_node_definitions, :key, unique: true
  end
end
