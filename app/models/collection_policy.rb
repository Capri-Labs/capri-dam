# Access-control entry linking a {UserGroup} to a {Collection} — the
# collection-scoped analogue of {FolderPolicy}.
#
# == Permission tiers
#
# | Column          | UI label          | Grants |
# |-----------------|-------------------|--------|
# | +view_access+   | Viewer            | View the workspace and its assets |
# | +edit_access+   | Editor            | Add/remove/pin assets, edit workspace properties |
# | +admin_access+  | Collection Admin  | Configure smart rules, manage access policies, delete/archive the workspace |
# | +explicit_deny+ | —                 | Short-circuits ALL access for this group, even if another group grants it |
#
# A group only needs the *highest* tier it should have — {Collection#editable_by?}
# and friends treat +admin_access+ as implying +edit_access+ implying +view_access+.
#
# Creating even one {CollectionPolicy} row for a collection switches that
# collection from "legacy open/allow-list" access (governed by the
# +allowed_groups+/+denied_groups+ JSONB arrays) into strict group-governed
# mode: only groups with an explicit policy (and no +explicit_deny+) may
# access it. See {Collection#accessible_by?}.
#
# @see Collection
# @see UserGroup
# @see FolderPolicy
class CollectionPolicy < ApplicationRecord
  belongs_to :collection
  belongs_to :user_group

  validates :view_access, :edit_access, :admin_access, :explicit_deny,
            inclusion: { in: [ true, false ] }
  validates :user_group_id, uniqueness: { scope: :collection_id }
end
