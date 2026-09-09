# frozen_string_literal: true

# Nightly integrity audit: re-reads a budgeted slice of the estate and compares
# each object's bytes against the digest recorded at ingest.
#
# == Why this runs at all
#
# Storage does not announce that it has lost something. Bit rot, a botched
# lifecycle-policy migration, a truncated multipart upload and a well-meaning
# bucket cleanup all present identically: the object is still listed, the
# metadata is still in Postgres, and nobody notices until the day somebody
# needs the file. By then the corruption has usually been replicated into every
# backup generation still retained, which is the failure that turns a recovery
# into a loss.
#
# The audit exists to shorten that window. It cannot prevent corruption; what
# it provides is a *date* — the last time these bytes were known good — so an
# operator restoring from backup knows which generation to reach for.
#
# == Queue & retries
#
# * Queue:   +preservation+ (weight 1 — this must always yield to user traffic)
# * Retries: 0 — a failed run is not worth retrying. The next scheduled run
#   picks up exactly the same work, because the queue is ordered by staleness
#   and nothing was marked as checked. Retrying would instead risk stacking
#   duplicate sweeps and doubling egress.
#
# @see Fixity::Sampler for how the slice is chosen
# @see Fixity::Verifier for how a single version is verified
class FixityAuditWorker
  include Sidekiq::Worker
  sidekiq_options queue: "preservation", retry: 0

  # @param batch_size [Integer, nil] override for the per-run budget
  def perform(batch_size = nil)
    limit = (batch_size.presence || Fixity::Sampler::DEFAULT_BATCH_SIZE).to_i
    tally = Hash.new(0)
    incidents = []

    Fixity::Sampler.due(limit: limit).each do |version|
      result = Fixity::Verifier.call(version)
      next if result.nil?

      tally[result.status] += 1
      incidents << version if %w[failed missing].include?(result.status)
    rescue StandardError => e
      # One unreadable row must not abort the sweep: the remaining versions in
      # this batch are the only ones that will be looked at today, and skipping
      # them costs a full re-check cycle of coverage.
      tally["error"] += 1
      Rails.logger.error("[FixityAudit] version=#{version.id} raised #{e.class}: #{e.message}")
    end

    Rails.logger.info("[FixityAudit] #{tally.map { |k, v| "#{k}=#{v}" }.join(" ")}")
    alert(incidents) if incidents.any?

    tally
  end

  private

  # A corruption finding is worthless if it only lands in a log file nobody
  # reads. Admins are notified directly, once per run rather than once per
  # asset, so a systemic failure (a bucket remounted read-only, say) produces
  # one actionable message instead of a thousand.
  def alert(incidents)
    subject = "Fixity audit found #{incidents.size} integrity #{"issue".pluralize(incidents.size)}"
    body = <<~HTML
      <p>The nightly fixity audit could not verify the following asset versions.</p>
      <ul>
        #{incidents.first(25).map { |v| "<li>Asset #{v.asset_id} &mdash; version #{v.version_number} (#{v.fixity_status})</li>" }.join}
      </ul>
      #{"<p>Further issues were found but are not listed here; see the preservation dashboard.</p>" if incidents.size > 25}
    HTML

    administrators.find_each do |admin|
      InboxDeliveryService.deliver(
        recipient: admin,
        subject: subject,
        body_html: body,
        message_type: "system",
        metadata: { "source" => "fixity_audit", "incident_count" => incidents.size },
      )
    rescue StandardError => e
      Rails.logger.error("[FixityAudit] Failed to notify user=#{admin.id}: #{e.message}")
    end
  end

  def administrators
    User.joins(:user_groups).where(user_groups: { slug: %w[administrators super-administrators] }).distinct
  end
end
