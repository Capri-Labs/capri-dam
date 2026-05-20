class CreateWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows do |t|
      t.string :name
      t.text :description
      t.integer :status
      t.string :trigger_type
      t.jsonb :metadata
      t.integer :created_by_id
      t.integer :updated_by_id

      t.timestamps
    end
  end
end
