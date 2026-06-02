class CreateSystemConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :system_configurations do |t|
      # The unique identifier (e.g., 'global_log_level', 'target_user_trace')
      t.string :key, null: false, index: { unique: true }

      # Allows the model to type-cast the string value back into its native format
      t.string :data_type, default: 'string', null: false

      # The active value
      t.text :value, null: false

      # The safety net. If 'expires_at' is reached, it reverts to this value.
      t.text :fallback_value

      # The TTL concept: Automatically turn off DEBUG mode at a certain time
      t.datetime :expires_at

      # For the Admin UI
      t.string :description

      # Audit trail: Which admin changed the log level?
      t.integer :updated_by_id, index: true

      t.timestamps
    end
  end
end