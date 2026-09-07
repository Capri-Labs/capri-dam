# A record that a file left the building through a distribution portal.
#
# WRITTEN ON DELIVERY, NOT ON INTENT
# ----------------------------------
# The row is created at the moment the bytes are handed over, not when the
# guest clicks. A log of attempted downloads answers a different and much less
# useful question than a log of completed ones, and "we think they may have
# taken it" is not something anyone can act on.
#
# NEVER FAILS THE DOWNLOAD IT MEASURES
# ------------------------------------
# {.record!} swallows its own errors. Tracking is valuable, but a partner
# being unable to collect their files because an audit insert hit a constraint
# is a worse outcome than a gap in the log — and the gap is visible, whereas a
# silently blocked download shows up as a support ticket days later.
class PortalDownload < ApplicationRecord
  belongs_to :review_link
  # Absent when the link never asked who the guest was.
  belongs_to :review_guest, optional: true
  belongs_to :asset

  # User agents are attacker-controlled and unbounded; keep the column honest.
  USER_AGENT_LIMIT = 500

  # Records a completed download.
  #
  # @param review_link [ReviewLink]
  # @param asset [Asset]
  # @param guest [ReviewGuest, nil]
  # @param request [ActionDispatch::Request, nil]
  # @return [PortalDownload, nil] nil if recording failed
  def self.record!(review_link:, asset:, guest: nil, request: nil)
    create!(
      review_link: review_link,
      asset: asset,
      review_guest: guest,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent&.to_s&.truncate(USER_AGENT_LIMIT),
    )
  rescue StandardError => e
    # Deliberately broad: nothing about measuring a download should be able to
    # prevent it. Logged so the gap is discoverable rather than silent.
    Rails.logger.warn("[PortalDownload] failed to record download of #{asset&.id} on link #{review_link&.id}: #{e.class}: #{e.message}")
    nil
  end
end
