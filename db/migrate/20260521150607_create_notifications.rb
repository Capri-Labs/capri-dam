class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.string :message
      t.string :action_url
      t.datetime :read_at

      t.timestamps
    end
  end
end
