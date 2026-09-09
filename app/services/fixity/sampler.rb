# frozen_string_literal: true

module Fixity
  # Chooses which versions to verify next.
  #
  # WHY SAMPLING RATHER THAN A FULL SWEEP
  # -------------------------------------
  # Verifying every object means downloading every object. On remote storage
  # that is an egress bill roughly equal to the size of the whole estate, and it
  # recurs on whatever cadence the sweep runs. A nightly full sweep is therefore
  # approved once and switched off after the first invoice, which leaves the
  # estate with no fixity checking at all — worse than a modest sample that
  # survives contact with the finance team.
  #
  # So the budget is fixed per run and the estate is treated as a queue ordered
  # by staleness. Every version is eventually reached, the slowest-moving part
  # of the collection is reached first, and the cost per day is a constant the
  # operator sets rather than a function of how much has been uploaded.
  #
  # WHY NEVER-CHECKED COMES FIRST
  # -----------------------------
  # A version that has never been verified has no evidence behind it at all,
  # while one verified last month has evidence that is merely old. Ordering
  # +last_fixity_check_at+ with NULLs first drains the unknown before refreshing
  # the known, so coverage climbs monotonically instead of oscillating.
  class Sampler
    # How long a passing result is treated as still meaningful. Re-checking
    # sooner spends egress to re-prove something recently proven.
    DEFAULT_RECHECK_AFTER = 90.days

    # Deliberately small. This is a background integrity audit competing with
    # user-facing work for the same storage bandwidth, and the useful property
    # is that it runs every day for years, not that any single run is thorough.
    DEFAULT_BATCH_SIZE = 250

    class << self
      # Versions that can be verified at all: they must carry both a digest to
      # compare against and a path to read from.
      #
      # @return [ActiveRecord::Relation]
      def verifiable
        AssetVersion
          .where("properties->>'checksum_sha256' IS NOT NULL")
          .where("properties->>'checksum_sha256' <> ''")
          .where("properties->>'storage_path' IS NOT NULL")
          .where("properties->>'storage_path' <> ''")
      end

      # Versions with bytes but no digest recorded at ingest. These are a
      # coverage gap, not a fault: there is nothing to compare against, so they
      # can never pass and must never be counted as failing.
      #
      # @return [ActiveRecord::Relation]
      def unverifiable
        AssetVersion
          .where("properties->>'storage_path' IS NOT NULL")
          .where("properties->>'storage_path' <> ''")
          .where("COALESCE(properties->>'checksum_sha256', '') = ''")
      end

      # The next slice of work, oldest evidence first.
      #
      # @param limit [Integer]
      # @param recheck_after [ActiveSupport::Duration]
      # @return [ActiveRecord::Relation]
      def due(limit: DEFAULT_BATCH_SIZE, recheck_after: DEFAULT_RECHECK_AFTER)
        verifiable
          .where("last_fixity_check_at IS NULL OR last_fixity_check_at < ?", recheck_after.ago)
          .order(Arel.sql("last_fixity_check_at ASC NULLS FIRST"))
          .limit(limit)
      end

      # Estate-wide position, for the dashboard and for arguing about budget.
      #
      # @return [Hash]
      def coverage(recheck_after: DEFAULT_RECHECK_AFTER)
        verifiable_count = verifiable.count
        checked = verifiable.where.not(last_fixity_check_at: nil).count
        stale = verifiable.where(last_fixity_check_at: ...recheck_after.ago).count

        {
          verifiable: verifiable_count,
          unverifiable: unverifiable.count,
          checked: checked,
          never_checked: verifiable_count - checked,
          stale: stale,
          due_now: [ verifiable_count - checked, 0 ].max + stale,
          coverage_percent: percentage(checked, verifiable_count),
          oldest_check_at: verifiable.where.not(last_fixity_check_at: nil).minimum(:last_fixity_check_at),
          by_status: verifiable.where.not(fixity_status: nil).group(:fixity_status).count,
        }
      end

      private

      def percentage(part, total)
        return 0.0 if total.zero?

        ((part.to_f / total) * 100).round(2)
      end
    end
  end
end
