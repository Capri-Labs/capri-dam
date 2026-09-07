# One asset a {ReviewLink} of kind +portal+ exposes, and what may be done
# with it.
#
# DEFAULT DENY
# ------------
# There is no row meaning "not shared" — absence *is* the denial. That matters
# more than it sounds: a collection gains assets over time, and a portal handed
# to a partner last month must not silently start offering them this month's
# unreleased work. Enumerating what is shared, rather than what is withheld,
# is the only version of that which fails safe.
#
# GRANTS ARE NOT THE LAST WORD
# ----------------------------
# A grant says the *sender* is willing. It does not say the asset may lawfully
# leave the building — that is {Rights::DownloadPolicy}'s question, and it is
# asked independently afterwards. A grant can never widen rights; it can only
# narrow what rights already allow.
class PortalGrant < ApplicationRecord
  # Ordered weakest to strongest; index position is the comparison.
  PERMISSIONS = %w[view download].freeze

  belongs_to :review_link
  belongs_to :asset

  validates :permission, presence: true, inclusion: { in: PERMISSIONS }
  validates :asset_id, uniqueness: { scope: :review_link_id }

  scope :downloadable, -> { where(permission: "download") }

  # @return [Boolean] whether this grant permits taking the file
  def download?
    permission == "download"
  end
end
