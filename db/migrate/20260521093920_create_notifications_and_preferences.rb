class CreateNotificationsAndPreferences < ActiveRecord::Migration[7.1]
  def change
    # 1. USER PREFERENCES
    # Separating this from the users table keeps the schema clean and makes it
    # easy to add new settings (e.g., SMS notifications, daily digests) later.
    create_table :user_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.boolean :receive_workflow_emails, default: true, null: false
      t.boolean :receive_mention_emails, default: true, null: false

      t.timestamps
    end

    # 2. IN-APP NOTIFICATIONS
    create_table :in_app_notifications do |t|
      # Who is receiving this notification?
      t.references :user, null: false, foreign_key: true

      # Who triggered it? (Optional: e.g., "John rejected your asset")
      t.references :actor, foreign_key: { to_table: :users }

      # What kind of notification is this? (e.g., 'task_assigned', 'workflow_rejected')
      t.string :action_type, null: false

      # Polymorphic association: Links directly to the Asset, Task, or Instance
      # so the UI knows exactly where to route the user when they click it.
      t.references :notifiable, polymorphic: true, null: false

      # A pre-computed message to keep frontend rendering incredibly fast
      t.string :message, null: false

      # If null, the notification is "unread". When clicked, we stamp this time.
      t.datetime :read_at

      t.timestamps
    end

    # Critical indexes for the UI top-bar badge (Count where read_at is null)
    add_index :in_app_notifications, [:user_id, :read_at]
  end
end