class AddJwtCredentialsToSystemConnectors < ActiveRecord::Migration[8.1]
  def change
    # "token"             — existing simple Bearer/Basic auth_token flow (unchanged)
    # "jwt_service_account" — Adobe IMS technical account (private-key JWT exchange)
    add_column :system_connectors, :credential_type, :string, default: "token", null: false

    # Encrypted-at-rest JSON blob holding the Adobe Developer Console technical
    # account payload (client_id, client_secret, private_key, technical_account_id,
    # org_id, ims_endpoint, metascopes, certificate_expiration_date). Never
    # exposed via the API — see SystemConnector#as_json.
    # NOTE: plain `text`, not jsonb — Rails ActiveRecord Encryption serializes
    # the JSON itself before encrypting; a jsonb column would double-cast the
    # ciphertext string as JSON and break (mirrors CdnConfiguration#settings).
    add_column :system_connectors, :credentials_payload, :text

    # Cached short-lived IMS access token + expiry, encrypted at rest.
    add_column :system_connectors, :access_token, :string
    add_column :system_connectors, :access_token_expires_at, :datetime
    add_column :system_connectors, :token_status, :string, default: "not_configured", null: false
    add_column :system_connectors, :last_token_refreshed_at, :datetime
    add_column :system_connectors, :last_token_error, :text

    # Folder the customer wants to scope a migration run to, e.g.
    # "/content/dam/US/marketing-assets/product-assets". Chosen per-run on the
    # connector (used as the default) and can be overridden per IngestionBatch.
    add_column :system_connectors, :default_source_path, :string

    add_column :ingestion_batches, :source_path, :string
  end
end
