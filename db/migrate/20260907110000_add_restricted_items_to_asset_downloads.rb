class AddRestrictedItemsToAssetDownloads < ActiveRecord::Migration[8.1]
  def change
    # Assets that were deliberately left out of a bulk export because their
    # rights did not permit it.
    #
    # This is not an error, so it does not belong in +error_message+ — the
    # download succeeded and the archive is valid. But a ZIP that silently omits
    # three files is worse than one that refuses to build: the recipient has no
    # way to know anything is missing and will assume the archive is complete.
    # Recording the exclusions structurally lets the UI say which assets were
    # withheld and why, rather than leaving the user to count files.
    add_column :asset_downloads, :restricted_items, :jsonb, null: false, default: []
  end
end
