class CreateEmailDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :email_deliveries do |t|
      t.string :recipient_email, null: false
      t.references :email_template, null: false, foreign_key: true
      t.string :status, default: 'pending', null: false # pending, sent, failed
      t.integer :retry_count, default: 0, null: false
      t.text :error_log

      # Stores the exact Liquid variables used at the time of sending for accurate retries
      t.jsonb :payload, default: {}, null: false

      t.timestamps
    end

    add_index :email_deliveries, :status
    add_index :email_deliveries, :recipient_email
    # Index for fast querying of JSONB data if needed later
    add_index :email_deliveries, :payload, using: :gin
  end
end