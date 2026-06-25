# frozen_string_literal: true

class ImageProfileFolderAssignment < ApplicationRecord
  belongs_to :image_profile
  # folder_id is a UUID string — no foreign-key constraint to folders table
  # because folders use a UUID primary key from a separate table.

  validates :image_profile_id, presence: true
  validates :folder_id,        presence: true
  validates :folder_id, uniqueness: { scope: :image_profile_id,
                                      message: "Profile is already applied to this folder." }
end
