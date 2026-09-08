# Automatic tag suggestions from a vision model at upload time.
#
# WHY SUGGESTIONS ARE NOT TAGS
# ----------------------------
# A tag is an assertion about an asset that people search on and make decisions
# from. A model's guess is not that until a person has agreed with it. Writing
# machine output straight into +assets.properties["tags"]+ would make the
# library's vocabulary a mixture of curated and speculative terms with nothing
# to tell them apart, and no way to undo a bad model run short of diffing
# history. So suggestions live in their own table with an explicit state, and
# only cross into the asset's real tags on accept.
#
# This mirrors the AI review pipeline (see {CreateAiReviews}), where findings
# also arrive as proposals a human triages rather than as facts.
#
# WHY THERE IS A RUN TABLE AS WELL
# --------------------------------
# The run is what makes the pipeline safe to retry. Dispatch is a no-op unless
# the run is still +queued+, so a Sidekiq retry cannot tag the same asset twice
# and double every label; and the callback has a row to correlate against and to
# refuse if it arrives late or twice. It is also where a failure becomes
# *visible* — without it, a gateway outage would look identical to a model that
# simply found nothing to say.
class CreateAiTagging < ActiveRecord::Migration[8.1]
  def change
    # One dispatch of one asset to the tagging capability.
    create_table :ai_tagging_runs, id: :uuid do |t|
      # assets.id and asset_versions.id are uuid.
      t.uuid :asset_id, null: false
      # Which version was actually looked at. Null for an asset-level run, but
      # recorded when known so a suggestion can be read back against the bytes
      # that produced it rather than whatever is current now.
      t.uuid :asset_version_id

      # Null for an automatic upload-time run: nobody asked for it, so there is
      # no one to attribute it to. Attributing it to the uploader would imply a
      # judgement they never made.
      t.references :requested_by, null: true, foreign_key: { to_table: :users }

      t.string :status, null: false, default: "queued"

      # An allow-listed capability key, never a free-text prompt from a client.
      # Free text would let a caller redirect the model to do something other
      # than tagging, at our cost and under our credentials.
      t.string :profile, null: false, default: "general_subject"

      # What produced the run: an upload, a person, or a batch sweep. Kept
      # because the right response to "these tags are wrong" differs — an
      # automatic run implicates the trigger settings, a manual one does not.
      t.string :trigger, null: false, default: "upload"

      # Recorded per run rather than read from configuration at display time:
      # the model that produced a suggestion is a fact about that suggestion,
      # and configuration changes.
      t.string :ai_model_name
      t.string :provider

      # Denormalised so a list of runs does not need a count per row.
      t.integer :suggestions_count, null: false, default: 0

      t.text :error_message
      t.jsonb :options, null: false, default: {}

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_foreign_key :ai_tagging_runs, :assets, column: :asset_id
    add_foreign_key :ai_tagging_runs, :asset_versions, column: :asset_version_id
    add_index :ai_tagging_runs, :asset_id
    add_index :ai_tagging_runs, [ :asset_id, :status ]

    add_check_constraint :ai_tagging_runs,
                         "status IN ('queued', 'running', 'completed', 'failed')",
                         name: "ai_tagging_runs_status_valid"

    add_check_constraint :ai_tagging_runs,
                         "trigger IN ('upload', 'manual', 'batch')",
                         name: "ai_tagging_runs_trigger_valid"

    # One proposed label.
    create_table :ai_tag_suggestions, id: :uuid do |t|
      t.references :ai_tagging_run, null: false, foreign_key: true, type: :uuid

      # Denormalised from the run so "what is pending on this asset" is one
      # index lookup rather than a join through every run the asset ever had.
      t.uuid :asset_id, null: false

      t.string :label, null: false

      # Null is meaningful: a model that does not report confidence is not the
      # same as one reporting zero. Nullable rather than defaulted so the
      # distinction survives.
      t.float :confidence

      # pending  — proposed, awaiting a person
      # accepted — copied into the asset's real tags
      # dismissed— rejected; kept rather than deleted so the same label is not
      #            proposed again on the next run and re-rejected forever
      t.string :state, null: false, default: "pending"

      t.references :decided_by, null: true, foreign_key: { to_table: :users }
      t.datetime :decided_at

      t.timestamps
    end

    add_foreign_key :ai_tag_suggestions, :assets, column: :asset_id
    add_index :ai_tag_suggestions, [ :asset_id, :state ]

    # One row per label per run: the same run proposing "sunset" twice would
    # make the accept/dismiss decision ambiguous.
    add_index :ai_tag_suggestions, [ :ai_tagging_run_id, :label ], unique: true

    add_check_constraint :ai_tag_suggestions,
                         "state IN ('pending', 'accepted', 'dismissed')",
                         name: "ai_tag_suggestions_state_valid"

    # A confidence outside 0..1 means the gateway and the application disagree
    # about the scale, which would silently corrupt every threshold comparison.
    add_check_constraint :ai_tag_suggestions,
                         "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)",
                         name: "ai_tag_suggestions_confidence_range"
  end
end
