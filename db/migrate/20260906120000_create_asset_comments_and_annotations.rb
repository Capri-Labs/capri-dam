class CreateAssetCommentsAndAnnotations < ActiveRecord::Migration[8.1]
  # General-purpose asset commenting + coordinate/timestamp annotations.
  #
  # Until now the only "comment" in the product was the single free-text
  # `workflow_tasks.comment` column attached to an approve/reject decision —
  # there was no way to discuss an asset outside a workflow, and no way to
  # point at a *region* of an image or a *moment* in a video.
  #
  # Three tables, deliberately separated:
  #
  #   comment_threads     — a conversation about an ASSET (version-independent)
  #   comments            — an utterance inside a thread, bound to ONE VERSION
  #   annotation_targets  — where on the media a comment points (0..n per comment)
  #
  # WHY THE THREAD IS VERSION-INDEPENDENT BUT THE COMMENT IS NOT
  # -----------------------------------------------------------
  # Every competing product (Frame.io, Ziflow, Bynder, Acquia DAM) binds a
  # comment to exactly one version and orphans it when a new version lands;
  # Acquia DAM documents that limitation explicitly. Keeping `asset_id` on the
  # thread and `asset_version_id` on the comment gives us both halves: each
  # comment still records precisely which version it was written against
  # (so the geometry means something), while the thread survives versioning
  # and can therefore carry a lifecycle — open -> addressed -> verified.
  # That lineage is what a later phase uses to answer "was this feedback
  # actually addressed in v3?" by re-projecting the annotation's bbox onto the
  # new version and running the pixel-diff that AssetVersionsTab already has.
  #
  # GEOMETRY STORAGE
  # ----------------
  # All spatial coordinates are NORMALISED to 0..1 with an upper-left origin,
  # never absolute pixels, so a region survives responsive layouts, renditions,
  # CDN transforms, and differing display sizes. Two representations are stored
  # together, on purpose:
  #
  #   * bbox_{x,y,w,h}  — always present, even for freehand. Cheap to index and
  #                       query; drives hit-testing, "comments near here"
  #                       lookups, and the version-diff region check.
  #   * svg_path        — the fidelity layer, expressed in a `viewBox="0 0 1 1"`
  #                       coordinate space so the browser can render it directly
  #                       into an <svg> overlay with no conversion. One field
  #                       covers ellipse, polygon, arrow and freehand alike.
  #
  # This follows the W3C Web Annotation Data Model's FragmentSelector /
  # SvgSelector split (https://www.w3.org/TR/annotation-model/), whose SvgSelector
  # requires shape dimensions to be relative to the source resource, and which
  # explicitly recommends AGAINST embedding style inside the SVG — hence the
  # separate `style` JSONB column.
  #
  # VIDEO TIME STORAGE
  # ------------------
  # Time is stored FRAME-NATIVE (`start_frame`/`end_frame` + `fps` +
  # `drop_frame`), not in milliseconds. Seconds and SMPTE timecode are both
  # derivable from frames, but frames cannot be recovered from a rounded
  # millisecond value — so millisecond storage permanently loses frame accuracy.
  # `end_frame` is what makes range ("in/out point") comments possible.
  def up
    # ── Threads ──────────────────────────────────────────────────────────────
    create_table :comment_threads, id: :uuid do |t|
      t.references :asset, null: false, foreign_key: true, type: :uuid

      # The version the conversation STARTED on. Kept for provenance even after
      # the thread is carried forward to newer versions.
      t.references :origin_version, foreign_key: { to_table: :asset_versions }, type: :uuid

      t.references :created_by, null: false, foreign_key: { to_table: :users }, type: :bigint

      # open      — awaiting action
      # addressed — author of the change believes it is handled (set on a newer version)
      # verified  — the original reviewer confirmed it
      # resolved  — closed without further action
      t.string :status, null: false, default: "open"

      # internal — only users with folder access
      # guest    — additionally visible to external share-link reviewers
      t.string :visibility, null: false, default: "internal"

      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: { to_table: :users }, type: :bigint

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :comment_threads, [ :asset_id, :status ]
    add_index :comment_threads, :deleted_at

    # ── Comments ─────────────────────────────────────────────────────────────
    create_table :comments, id: :uuid do |t|
      t.references :comment_thread, null: false, foreign_key: true, type: :uuid

      # Which version this was written against. Nullable so a comment survives
      # hard-deletion of a version row rather than cascading away.
      t.references :asset_version, foreign_key: true, type: :uuid

      # Single-level replies (a reply's parent is always a root comment).
      t.references :parent_comment, foreign_key: { to_table: :comments }, type: :uuid

      t.text :body, null: false

      # W3C Web Annotation Data Model motivation, §3.3.5. Lets the UI and any
      # future export distinguish a plain remark from a change request.
      t.string :motivation, null: false, default: "commenting"

      # Nullable: a comment may be authored by a non-human agent.
      t.references :author, foreign_key: { to_table: :users }, type: :bigint

      # person | software — the W3C model has a `Software` agent class precisely
      # so machine-generated annotations are first-class. An AI review assistant
      # writes `software` comments that a human can later promote.
      t.string :agent_type, null: false, default: "person"
      t.string :agent_name

      # 0..1 confidence for software-authored comments; NULL for humans.
      t.decimal :confidence, precision: 5, scale: 4

      t.datetime :edited_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :comments, [ :comment_thread_id, :created_at ]
    add_index :comments, :deleted_at

    # ── Annotation targets ───────────────────────────────────────────────────
    create_table :annotation_targets, id: :uuid do |t|
      t.references :comment, null: false, foreign_key: true, type: :uuid

      # image | video | document
      t.string :media_type, null: false, default: "image"

      # pin | rect | ellipse | arrow | line | freehand | text | highlight
      t.string :shape, null: false, default: "pin"

      # Normalised 0..1 bounding box, upper-left origin. Always populated —
      # for a pin, w/h are 0.
      t.float :bbox_x, null: false, default: 0.0
      t.float :bbox_y, null: false, default: 0.0
      t.float :bbox_w, null: false, default: 0.0
      t.float :bbox_h, null: false, default: 0.0

      # Geometry-only SVG path in a `viewBox="0 0 1 1"` space (no styling).
      t.text :svg_path

      # ── Temporal (video) ──
      t.integer :start_frame
      t.integer :end_frame          # NULL => point-in-time; set => range comment
      t.decimal :fps, precision: 8, scale: 4
      t.boolean :drop_frame, null: false, default: false

      # ── Document ──
      t.integer :page
      t.text :text_exact            # W3C TextQuoteSelector — survives reflow
      t.text :text_prefix
      t.text :text_suffix
      t.integer :text_start         # W3C TextPositionSelector — brittle, but exact
      t.integer :text_end

      # ── Provenance of the media AS IT WAS ANNOTATED ──
      # Captured so a later phase can re-project this geometry onto a version
      # that has been rotated or cropped, instead of silently misplacing the pin.
      t.integer :source_width
      t.integer :source_height
      t.integer :source_rotation, null: false, default: 0
      t.jsonb :source_crop

      # Stroke colour/width/opacity. `stroke_width` is stored as a FRACTION of
      # the shorter source dimension, not pixels, so it scales with the media.
      t.jsonb :style, null: false, default: {}

      t.string :label

      t.timestamps
    end

    # NOTE: `t.references` above already indexes comment_id.
    add_index :annotation_targets, [ :media_type, :shape ]
    # Supports "which annotations fall in this region of the frame?" for the
    # version-diff / was-it-addressed check.
    add_index :annotation_targets, [ :bbox_x, :bbox_y ]
    add_index :annotation_targets, [ :start_frame, :end_frame ]

    # Reject out-of-range geometry at the database level — a normalised
    # coordinate outside 0..1 is always a bug, and silently storing it would
    # render the annotation off-screen with no clue why.
    execute <<~SQL
      ALTER TABLE annotation_targets
        ADD CONSTRAINT chk_annotation_targets_bbox_normalised
        CHECK (
          bbox_x >= 0 AND bbox_x <= 1 AND
          bbox_y >= 0 AND bbox_y <= 1 AND
          bbox_w >= 0 AND bbox_w <= 1 AND
          bbox_h >= 0 AND bbox_h <= 1 AND
          bbox_x + bbox_w <= 1.0001 AND
          bbox_y + bbox_h <= 1.0001
        );
    SQL

    # A range comment must not end before it starts.
    execute <<~SQL
      ALTER TABLE annotation_targets
        ADD CONSTRAINT chk_annotation_targets_frame_range
        CHECK (end_frame IS NULL OR start_frame IS NULL OR end_frame >= start_frame);
    SQL
  end

  def down
    execute "ALTER TABLE annotation_targets DROP CONSTRAINT IF EXISTS chk_annotation_targets_frame_range"
    execute "ALTER TABLE annotation_targets DROP CONSTRAINT IF EXISTS chk_annotation_targets_bbox_normalised"
    drop_table :annotation_targets
    drop_table :comments
    drop_table :comment_threads
  end
end
