class UserGroupClosure < ApplicationRecord
  # Inform Rails this table has no standard 'id' column
  self.primary_key = nil

  belongs_to :ancestor, class_name: "UserGroup"
  belongs_to :descendant, class_name: "UserGroup"
end
