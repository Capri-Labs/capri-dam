# Backs the new direct "Publish"/"Unpublish" REST action (Api::V1::AssetsController#publish
# / #unpublish). Decoupled from the existing `status` lifecycle enum (draft/pending/.../ready)
# on purpose — publishing is an explicit, user-driven visibility toggle, independent from the
# automatic processing pipeline, and previously only existed indirectly via the workflow
# `PublishNode` (which sets `status: "approved"`, a different concept). A nil value means
# "not published"; a timestamp records when the asset was last published.
class AddPublishedAtToAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :assets, :published_at, :datetime
    add_index :assets, :published_at
  end
end
