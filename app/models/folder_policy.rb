class FolderPolicy < ApplicationRecord
  belongs_to :folder
  belongs_to :user_group

  # Ensure boolean defaults are respected and validated
  validates :read_access, :write_access, :delete_access, :manage_access, :approval_flow, :explicit_deny, inclusion: { in: [true, false] }
end