# Adds support for metadata/tag-only smart collection rules (no semantic AI
# prompt required) alongside the existing semantic-vector matching:
#
# * +match_mode+ — "semantic" (default, preserves existing behavior),
#   "metadata" (pure tag/property matching, no embedding needed), or
#   "hybrid" (both must pass).
# * +semantic_prompt+ is relaxed to nullable since metadata-only rules have
#   no AI prompt at all.
# * +prompt_vector+ stores the embedding generated for +semantic_prompt+ once
#   the AI gateway integration populates it (previously referenced by
#   {SmartCollectionRouterWorker} but never actually persisted anywhere).
class AddMatchModeToCollectionRules < ActiveRecord::Migration[8.1]
  def up
    add_column :collection_rules, :match_mode, :string, default: "semantic", null: false
    add_column :collection_rules, :prompt_vector, :jsonb

    change_column_null :collection_rules, :semantic_prompt, true
  end

  def down
    change_column_null :collection_rules, :semantic_prompt, false

    remove_column :collection_rules, :prompt_vector
    remove_column :collection_rules, :match_mode
  end
end
