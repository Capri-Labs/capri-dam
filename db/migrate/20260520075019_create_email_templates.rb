class CreateEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :email_templates do |t|
      t.string :name, null: false             # e.g., "Standard Welcome Email"
      t.string :event_trigger, null: false    # e.g., "user_created"
      t.string :subject, null: false          # Can contain {{ user.name }}
      t.text :html_body
      t.text :text_body
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    # Ensure we only have one active template per trigger type
    add_index :email_templates, :event_trigger, unique: true
  end
end