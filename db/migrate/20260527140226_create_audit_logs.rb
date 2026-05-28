class CreateAuditLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: true, foreign_key: true
      t.string :action
      t.string :auditable_type
      t.integer :auditable_id
      t.jsonb :changes_data
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    # Explicitly name the index so it is under 63 characters
    add_index :audit_logs,
              [:auditable_type, :auditable_id, :ip_address, :user_id],
              name: "idx_audit_logs_polymorphic_ip_user"
  end
end