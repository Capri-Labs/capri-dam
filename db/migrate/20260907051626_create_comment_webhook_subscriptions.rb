# Outbound webhook registrations for review activity.
#
# The workflow engine already fires webhooks, but only as a configured *step*
# inside a workflow — there was no way to subscribe to something simply
# happening. Review activity is exactly that kind of event: a proofing vendor
# or a project tracker wants to know when a comment is posted, not to be wired
# into an approval chain.
class CreateCommentWebhookSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :comment_webhook_subscriptions do |t|
      t.string  :name,    null: false
      t.string  :url,     null: false
      # Signing secret. Stored so deliveries can be verified by the receiver;
      # never emitted by the API.
      t.string  :secret,  null: false
      # Which events this endpoint wants. An empty list means "all", which is
      # the useful default for a general-purpose integration.
      t.jsonb   :events,  null: false, default: []
      t.boolean :active,  null: false, default: true

      # Scoping a subscription to one asset or folder keeps a noisy integration
      # from receiving every comment in the estate. Both nil means everything.
      t.uuid    :asset_id
      t.uuid    :folder_id

      t.references :created_by, foreign_key: { to_table: :users }

      # Delivery health, so a broken endpoint is visible without trawling logs.
      t.datetime :last_delivered_at
      t.integer  :last_status
      t.text     :last_error
      t.integer  :consecutive_failures, null: false, default: 0

      t.timestamps
    end

    add_index :comment_webhook_subscriptions, :active
    add_index :comment_webhook_subscriptions, :asset_id
    add_index :comment_webhook_subscriptions, :folder_id
  end
end
