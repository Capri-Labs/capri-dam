# frozen_string_literal: true

# Join model associating a {VideoProfile} with a folder (by UUID).
#
# The +folder_id+ column stores a UUID string; no database-level foreign key is
# created because folders use a UUID primary key type from a separate table.
class VideoProfileFolderAssignment < ApplicationRecord
  belongs_to :video_profile

  validates :video_profile_id, presence: true
  validates :folder_id,        presence: true
  validates :folder_id, uniqueness: { scope: :video_profile_id,
                                      message: "Profile is already applied to this folder." }
end
