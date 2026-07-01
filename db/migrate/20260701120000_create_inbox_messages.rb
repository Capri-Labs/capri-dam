class CreateInboxMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :inbox_messages, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users }, type: :bigint
      t.references :sender, foreign_key: { to_table: :users }, type: :bigint
      t.string :subject
      t.text :body_html
      t.text :body_text
      t.string :message_type, null: false, default: "notification"
      t.datetime :read_at
      t.datetime :archived_at
      t.datetime :starred_at
      t.references :email_template, foreign_key: true, type: :bigint
      t.string :reference_type
      t.uuid :reference_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :inbox_messages, %i[recipient_id read_at]
    add_index :inbox_messages, :message_type
    add_index :inbox_messages, %i[recipient_id archived_at]
  end
end
