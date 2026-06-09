class UpgradeCollectionsForSmartRouting < ActiveRecord::Migration[7.0]
  def change
    # 1. Expand Collections for Operational Governance
    # 'collection_type' dictates UI behavior (e.g., 'manual' vs 'smart')
    add_column :collections, :collection_type, :string, default: 'manual', null: false

    # 'expires_at' enables Time-to-Live (TTL) auto-archiving for zero-noise operations
    add_column :collections, :expires_at, :datetime

    # 2. Expand CollectionAssets for Auditability
    # If an AI rule pulls an asset in, we MUST track which rule did it.
    # If this is null, it means a human manually staged the asset.
    add_reference :collection_assets, :collection_rule, null: true, foreign_key: true

    # A boolean flag allowing curators to "pin" an asset so AI never removes it
    add_column :collection_assets, :pinned, :boolean, default: false, null: false
  end
end