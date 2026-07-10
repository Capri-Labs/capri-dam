# CodeQL flagged EmailDelivery#payload as clear-text storage of sensitive
# data: Admin::UsersController#create passes the plaintext temporary
# password into EmailOrchestrator.trigger, which persists it verbatim in
# this JSONB column until EmailDispatcherWorker consumes it. Encrypting the
# column at rest (matching the existing SystemConnector#credentials_payload
# / CdnConfiguration#settings pattern) closes that gap without changing the
# async delivery flow.
#
# ActiveRecord Encryption cannot encrypt a `jsonb` column directly (the
# resulting ciphertext is a string, not valid JSON), so we first cast it to
# `text` -- the GIN index existed to support querying the JSON payload
# directly, which no code in the app actually does, so it is safe to drop.
class EncryptEmailDeliveriesPayload < ActiveRecord::Migration[8.1]
  def up
    remove_index :email_deliveries, :payload, if_exists: true
    change_column :email_deliveries, :payload, :text, default: "{}", null: false,
      using: "payload::text"
  end

  def down
    change_column :email_deliveries, :payload, :jsonb, default: {}, null: false,
      using: "payload::jsonb"
    add_index :email_deliveries, :payload, using: :gin
  end
end
