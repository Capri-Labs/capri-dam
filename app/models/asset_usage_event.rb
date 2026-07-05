# Records a single app-observed usage event (view / download / share) for an
# {Asset}, powering {Asset#usage_stats}.
#
# Kept as a dedicated table rather than folded into {AuditLog} because
# +audit_logs.auditable_id+ is an +integer+ column sized for {User}'s bigint
# ids, while {Asset} ids are UUIDs — a polymorphic reference there would
# silently truncate/corrupt the id.
#
# @see Api::V1::AssetsController#track_event
class AssetUsageEvent < ApplicationRecord
  EVENT_TYPES = %w[view download share].freeze

  belongs_to :asset
  belongs_to :user

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
end
