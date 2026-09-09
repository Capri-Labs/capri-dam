# Fixity auditing: proving the bytes are still the bytes.
#
# WHY THIS EXISTS
# ---------------
# +checksum_sha256+ is computed once, at ingest, and then never looked at again
# except to detect duplicates. That makes it a record of what the file was on
# the day it arrived, not evidence of what it is now. Silent corruption, a
# half-completed storage migration, a truncated multipart upload, or a bucket
# lifecycle rule that quietly transitioned an object all produce a file that
# still exists, still has the right size in the database, and no longer decodes.
# Nothing in the system would notice. The person who notices is whoever opens
# the file — typically years later, long past the point where a backup could
# have been restored.
#
# WHY A HISTORY TABLE AND NOT A COLUMN
# ------------------------------------
# A single +verified_at+ column answers "is it good now" and destroys the far
# more useful question: *when did it stop being good*. The window between the
# last passing check and the first failing one is what tells an operator which
# backup generation is still trustworthy, and whether an incident touched one
# object or ten thousand. That is a history, so it is stored as one.
#
# WHY THERE ARE ALSO TWO COLUMNS ON asset_versions
# ------------------------------------------------
# Scheduling is the hard part of fixity, not hashing. Choosing what to verify
# next means ordering the entire estate by staleness, and doing that against the
# history table needs a correlated "latest check per version" subquery on every
# run. The two denormalised columns make the sampling query an index scan.
# They are a cache of the newest row in +fixity_checks+, not a second source of
# truth.
class CreateFixityAndPreservation < ActiveRecord::Migration[8.1]
  def change
    # One verification attempt against one version's bytes.
    create_table :fixity_checks, id: :uuid do |t|
      # assets.id and asset_versions.id are uuid.
      t.uuid :asset_id, null: false
      t.uuid :asset_version_id, null: false

      # passed     — recomputed digest equals the digest recorded at ingest
      # failed     — the bytes are readable and they are NOT what they were.
      #              This is the alarm: it means corruption or substitution.
      # missing    — the object is not in the store at all. Different from
      #              failed, and a different incident: failed implicates the
      #              bytes, missing implicates the storage layer or the path.
      # unreadable — the store refused or the transfer broke. This is an
      #              inconclusive result, not a verdict on the file, and must
      #              never be reported as if the asset were corrupt.
      t.string :status, null: false

      # Both digests are kept, including on success. On failure the pair is the
      # evidence; keeping it only on failure would mean the passing history
      # could not be audited later.
      t.string :expected_checksum
      t.string :actual_checksum

      # Observed at read time rather than copied from metadata: a truncated
      # object is the common corruption, and its recorded size is still the
      # original one.
      t.bigint :byte_size

      # Where it was read from, recorded per check. Storage configuration
      # changes, and "which backend was this verified against" stops being
      # answerable the moment the active adapter is switched.
      t.string :storage_path
      t.string :storage_backend

      # Cost signal. Fixity is an egress bill, and the only way to argue about
      # the sampling budget is to know what a check actually costs.
      t.integer :duration_ms

      t.text :error_message

      # Distinct from created_at so a backfilled or imported result can carry
      # the time the verification really happened.
      t.datetime :checked_at, null: false

      t.timestamps
    end

    add_foreign_key :fixity_checks, :assets, column: :asset_id
    add_foreign_key :fixity_checks, :asset_versions, column: :asset_version_id

    # "History for this version, newest first" — the audit view.
    add_index :fixity_checks, [ :asset_version_id, :checked_at ]
    # "What is currently wrong across the estate" — the alerting view.
    add_index :fixity_checks, [ :status, :checked_at ]
    add_index :fixity_checks, :asset_id

    add_check_constraint :fixity_checks,
                         "status IN ('passed', 'failed', 'missing', 'unreadable')",
                         name: "fixity_checks_status_valid"

    # NULL means never verified, which is deliberately distinct from "verified
    # and fine". A default of the current time would have marked the entire
    # existing estate as freshly checked without a single byte being read.
    add_column :asset_versions, :last_fixity_check_at, :datetime
    add_column :asset_versions, :fixity_status, :string

    add_check_constraint :asset_versions,
                         "fixity_status IS NULL OR fixity_status IN " \
                         "('passed', 'failed', 'missing', 'unreadable')",
                         name: "asset_versions_fixity_status_valid"

    # The sampler orders by this column with NULLs first, so never-checked
    # versions are always drained before anything is re-checked.
    add_index :asset_versions, :last_fixity_check_at
    # Partial: the failures are a tiny fraction of the table and are read on
    # every dashboard load.
    add_index :asset_versions, :fixity_status,
              where: "fixity_status IS NOT NULL AND fixity_status <> 'passed'",
              name: "index_asset_versions_on_unhealthy_fixity_status"
  end
end
