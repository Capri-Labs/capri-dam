class CreateAiReviews < ActiveRecord::Migration[8.1]
  def change
    # One run of the review assistant against one version of one asset.
    #
    # The run is recorded separately from its findings so that "the assistant
    # looked at this and found nothing" is distinguishable from "the assistant
    # never ran" — without a run row those two states are identical, and a
    # reviewer would have no way to tell silence from absence.
    create_table :ai_reviews, id: :uuid do |t|
      t.references :asset, null: false, type: :uuid, foreign_key: true
      # The version actually inspected. Findings carry coordinates, which are
      # only meaningful against the frame they were drawn on.
      t.references :asset_version, null: true, type: :uuid, foreign_key: true
      t.references :requested_by, null: true, foreign_key: { to_table: :users }

      t.string :status, null: false, default: "queued"
      t.string :profile, null: false, default: "brand_guidelines"

      # Which model produced the findings, captured at run time rather than
      # looked up later: model configuration changes, and a finding has to stay
      # attributable to the thing that actually made it.
      #
      # Named +ai_model_name+ because +model_name+ is an Active Record class
      # method; a column of that name raises DangerousAttributeError on load.
      t.string :ai_model_name
      t.string :provider

      t.integer :findings_count, null: false, default: 0
      t.text :error_message
      t.jsonb :options, null: false, default: {}

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_reviews, %i[asset_id created_at]
    add_index :ai_reviews, :status

    # A finding is a real thread, so it inherits annotation geometry,
    # versioning and region-diff for free. What makes it a *suggestion* rather
    # than an accepted remark is this triage state, which is NULL for every
    # human-authored thread.
    add_reference :comment_threads, :ai_review, type: :uuid, null: true, foreign_key: true
    add_column :comment_threads, :suggestion_state, :string, null: true
    add_reference :comment_threads, :suggestion_decided_by, null: true, foreign_key: { to_table: :users }
    add_column :comment_threads, :suggestion_decided_at, :datetime

    # Partial index: the pending-suggestion queue is the only hot query here,
    # and human threads (the overwhelming majority) are excluded from the index
    # entirely.
    add_index :comment_threads,
              %i[asset_id suggestion_state],
              where: "suggestion_state IS NOT NULL",
              name: "index_comment_threads_on_pending_suggestions"

    # The existing constraint predates machine authorship and requires a user
    # or a guest. An assistant-authored thread has neither, so it would be
    # rejected outright. Widening it rather than dropping it keeps the original
    # guarantee intact: a thread still cannot be anonymous — it is now
    # attributable to a person, a guest, *or* a recorded assistant run.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE comment_threads
            DROP CONSTRAINT IF EXISTS comment_threads_have_an_author
        SQL
        execute <<~SQL.squish
          ALTER TABLE comment_threads
            ADD CONSTRAINT comment_threads_have_an_author
            CHECK (
              created_by_id IS NOT NULL
              OR created_by_guest_id IS NOT NULL
              OR ai_review_id IS NOT NULL
            )
        SQL
      end

      dir.down do
        execute <<~SQL.squish
          ALTER TABLE comment_threads
            DROP CONSTRAINT IF EXISTS comment_threads_have_an_author
        SQL
        execute <<~SQL.squish
          ALTER TABLE comment_threads
            ADD CONSTRAINT comment_threads_have_an_author
            CHECK (
              created_by_id IS NOT NULL
              OR created_by_guest_id IS NOT NULL
            )
        SQL
      end
    end
  end
end
