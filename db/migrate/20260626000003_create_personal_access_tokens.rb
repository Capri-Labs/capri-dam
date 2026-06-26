# Personal Access Tokens (PATs) — long-lived bearer tokens for CLI / API access.
#
# * token_digest  — SHA-256 of the raw token; never stored in plaintext.
# * last_four     — last 4 chars of raw token; shown in the UI so the user
#                   can identify a token without re-revealing the secret.
# * expires_at    — NULL means the token never expires.
# * active        — soft-revocation flag; false = immediately invalid.
class CreatePersonalAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_access_tokens do |t|
      t.bigint  :user_id,      null: false
      t.string  :name,         null: false
      t.string  :token_digest, null: false
      t.string  :last_four,    null: false
      t.string  :scopes,       default: "read"
      t.datetime :last_used_at
      t.datetime :expires_at
      t.boolean :active,       default: true, null: false

      t.timestamps
    end

    add_index :personal_access_tokens, :user_id
    add_index :personal_access_tokens, :token_digest, unique: true
    add_index :personal_access_tokens, [ :user_id, :active ]
  end
end

