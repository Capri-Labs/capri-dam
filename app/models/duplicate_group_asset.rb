# Join record connecting a {DuplicateGroup} to one of its member {Asset}s.
#
# The +is_original+ flag is +true+ for the earliest-created asset in the
# group (i.e. the one with the oldest +created_at+).  The UI uses this hint
# to suggest which copy to keep.
#
# @see DuplicateGroup
# @see Asset
class DuplicateGroupAsset < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :duplicate_group, foreign_key: :duplicate_group_id,
             inverse_of: :duplicate_group_assets

  belongs_to :asset, foreign_key: :asset_id, primary_key: :id

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :duplicate_group_id, presence: true
  validates :asset_id, presence: true,
            uniqueness: { scope: :duplicate_group_id,
                          message: "is already a member of this duplicate group" }
end
