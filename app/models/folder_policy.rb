# Access-control entry linking a {UserGroup} to a {Folder}.
#
# == Permission matrix
#
# | Column            | UI label   | What it grants |
# |-------------------|------------|----------------|
# | +read_access+     | Read       | View assets & child folders |
# | +modify_access+   | Modify     | Edit existing asset metadata / rename folders |
# | +create_access+   | Create     | Upload assets / create sub-folders |
# | +delete_access+   | Delete     | Delete assets and folders |
# | +replicate_access+| Replicate  | Push assets to CDN |
# | +manage_access+   | Manage     | Reserved — admin-level folder config |
# | +explicit_deny+   | —          | Short-circuits ALL permissions even for inherited allows |
#
# == Inheritance
#
# Policies set on a parent folder are **inherited** by child folders unless
# overridden by an explicit policy directly on the child.  The aggregation
# algorithm in {User#permissions_for} honours this.
#
# @see User#permissions_for
# @see UserGroup
class FolderPolicy < ApplicationRecord
  belongs_to :folder
  belongs_to :user_group

  validates :read_access, :modify_access, :create_access, :delete_access,
            :replicate_access, :manage_access, :explicit_deny,
            inclusion: { in: [true, false] }
end