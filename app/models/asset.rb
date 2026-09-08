# Core digital-asset domain model for the Capri DAM platform.
#
# An +Asset+ represents a single media item (image, video, document, …) owned
# by a {User} and optionally placed inside a {Folder}.  The binary file is
# **never** stored directly on the asset row; instead each upload or edit
# creates an immutable {AssetVersion} snapshot.  The currently active version
# is tracked via the +active_version_id+ foreign key so that version history
# is always preserved.
#
# == Status lifecycle
#
#   draft → pending → processing → ready
#                               ↓
#                          in_review → approved / rejected
#                               ↓
#                             failed (terminal, retryable by support)
#
# == AI / Vector search
#
# After every save that touches +properties+, the model publishes an
# +asset.needs_embedding+ event over Redis so that an external AI gateway can
# generate and store a semantic vector in the associated {AssetEmbedding}.
# The {.nearest_to_vector} scope then enables cosine-similarity search using
# the +neighbor+ gem.
#
# == Soft deletion
#
# Assets are never hard-deleted by end users.  {SoftDeletable} provides the
# +deleted_at+ semantics; permanently removing an asset (with all physical
# files) is an explicit admin operation in {Api::V1::AssetsController#permanent_delete}.
#
# @see AssetVersion
# @see AssetEmbedding
# @see SoftDeletable
class Asset < ApplicationRecord
  include SoftDeletable

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  # @!attribute [r] user
  #   @return [User] the owner who uploaded the asset
  belongs_to :user

  # @!attribute [r] folder
  #   @return [Folder, nil] the folder this asset lives in; +nil+ means root
  belongs_to :folder, optional: true

  # @!attribute [r] asset_versions
  #   @return [ActiveRecord::Associations::CollectionProxy<AssetVersion>]
  #     all immutable snapshots of this asset, ordered by creation time
  has_many :asset_versions, dependent: :destroy

  # @!attribute [r] renditions
  #   @return [ActiveRecord::Associations::CollectionProxy<Rendition>]
  #     alternative forms of this same work (print, social, proxy). Unlike
  #     versions these are all current at once; see {Rendition}.
  #
  # +dependent: :destroy+ rather than +delete_all+ so each row's
  # +after_destroy_commit+ runs and its stored object is purged. Assets are
  # soft-deleted into the bin, so this only fires on a real purge — which is
  # exactly when the bytes should go.
  has_many :renditions, dependent: :destroy

  # @!attribute [r] active_version
  #   @return [AssetVersion, nil] the version currently presented to consumers
  belongs_to :active_version, class_name: "AssetVersion", optional: true

  has_many :workflow_instances, dependent: :destroy

  # @!attribute [r] comment_threads
  #   @return [ActiveRecord::Associations::CollectionProxy<CommentThread>]
  #     review conversations about this asset. Threads hang off the *asset*,
  #     not off a version, so feedback survives a re-upload; each individual
  #     {Comment} records the {AssetVersion} it was written against.
  has_many :comment_threads, dependent: :destroy

  # @!attribute [r] ai_reviews
  #   @return [ActiveRecord::Associations::CollectionProxy<AiReview>]
  #     runs of the AI review assistant against this asset. Destroyed with the
  #     asset — without this the foreign key blocks deleting any asset that has
  #     ever been reviewed.
  has_many :ai_reviews, dependent: :destroy

  # ActiveStorage attachment on the asset itself (legacy; new uploads use AssetVersion#file).
  has_one_attached :file

  # @!attribute [r] asset_embedding
  #   @return [AssetEmbedding, nil] the AI vector for semantic similarity search
  has_one :asset_embedding,          dependent: :destroy
  has_one :asset_provenance_record,  dependent: :destroy, foreign_key: :asset_id, primary_key: :id

  has_many :collection_assets, dependent: :destroy

  # @!attribute [r] scheduled_publish_actions
  #   @return [ActiveRecord::Associations::CollectionProxy<ScheduledPublishAction>]
  #     pending/completed "Publish Later"/"Unpublish Later" requests for this asset
  has_many :scheduled_publish_actions, dependent: :destroy

  # @!attribute [r] duplicate_group_assets
  #   @return [ActiveRecord::Associations::CollectionProxy<DuplicateGroupAsset>]
  #     join rows linking this asset to any {DuplicateGroup}s it was flagged
  #     in. `dependent: :destroy` is a safety net for destroy paths that
  #     don't explicitly call {DuplicateGroupAsset.cleanup_for_asset!}
  #     first (e.g. cascading from `Folder#destroy`) — without it, hard
  #     deletion raises `ActiveRecord::InvalidForeignKey`.
  has_many :duplicate_group_assets, dependent: :destroy

  # @!attribute [r] collections
  #   @return [ActiveRecord::Associations::CollectionProxy<Collection>]
  has_many :collections, through: :collection_assets

  # @!attribute [r] asset_usage_events
  #   @return [ActiveRecord::Associations::CollectionProxy<AssetUsageEvent>]
  #     app-observed view/download/share events; see {#usage_stats}
  has_many :asset_usage_events, dependent: :destroy

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :title, presence: true

  # The vocabulary is also enforced by a CHECK constraint on the column; this
  # turns what would be a 500 from the database into a 422 with a usable
  # message.
  validates :usage_terms, inclusion: { in: Rights::UsageTerms::CODES }

  validate :license_expiry_must_be_parseable

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------

  # @!attribute [rw] status
  #   @return [String] current processing / approval state of the asset
  #
  # NOTE: the backing column (`assets.status`) is a string, so the enum must
  # map to string values (not the default integer indices) or every read
  # after a save/reload silently returns nil (the integer DB value can never
  # match the string stored by ActiveRecord's type cast).
  enum :status, {
    draft:      "draft",
    pending:    "pending",
    processing: "processing",
    ready:      "ready",
    in_review:  "in_review",
    approved:   "approved",
    rejected:   "rejected",
    failed:     "failed",
  }, default: :draft

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  # Active (non-deleted) assets that have been fully processed and published.
  #
  # NOTE: this pre-dates, and is unrelated to, {#published?}/{#published_at} —
  # it reflects the automatic *processing* pipeline reaching its terminal
  # "ready" state, not the explicit, user-driven publish/unpublish toggle
  # added later (see {Api::V1::AssetsController#publish}). Kept as-is (rather
  # than renamed) to avoid touching its one existing call site
  # ({Api::V1::CollectionsController#simulated_matches}).
  # @return [ActiveRecord::Relation]
  scope :published, -> { where(status: :ready) }

  # Assets explicitly published via {#publish!} (i.e. +published_at+ is set).
  # Independent of {.published}/+status+ — see {#published?} for details.
  # @return [ActiveRecord::Relation]
  scope :currently_published, -> { where.not(published_at: nil) }

  # Nearest-neighbour cosine search using the +neighbor+ gem and pgvector.
  #
  # @param vector [Array<Float>] the query embedding (must match stored dimensions)
  # @return [ActiveRecord::Relation] assets ordered by cosine similarity, closest first
  scope :nearest_to_vector, ->(vector) {
    return none if vector.blank?

    joins(:asset_embedding)
      .merge(AssetEmbedding.nearest_neighbors(:embedding, vector, distance: "cosine"))
      .select("assets.*")
  }

  # Assets whose licence window has closed. An asset with no recorded expiry is
  # not expired — "no expiry" and "unknown expiry" are deliberately different
  # states, and only the former is stored.
  # @return [ActiveRecord::Relation]
  scope :license_expired, ->(at = Time.current) {
    where.not(license_expires_at: nil).where(license_expires_at: ...at)
  }

  # @return [ActiveRecord::Relation] assets still inside their licence window
  #   (including those that never had one)
  scope :license_current, ->(at = Time.current) {
    where(license_expires_at: nil).or(where(license_expires_at: at..))
  }

  # Assets expiring within the given window — the query behind the expiry
  # forecast in {Reports::AnalyticsService}. Bounded at both ends, because an
  # asset that expired last year is a different problem from one expiring next
  # week, and lumping them together was how the old unbounded JSONB cast
  # reported "expiring soon" for assets whose typo'd dates landed in antiquity.
  # @return [ActiveRecord::Relation]
  scope :license_expiring_within, ->(window, from: Time.current) {
    where(license_expires_at: from..(from + window))
  }

  # @return [ActiveRecord::Relation] assets whose terms permit distribution
  #   outside the organisation, ignoring expiry
  scope :externally_distributable, -> {
    where(usage_terms: Rights::UsageTerms::TERMS.select { |_, v| v[:external] }.keys)
  }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  # Publishes an embedding-request event to Redis after every create/update.
  after_commit :broadcast_for_embedding, on: [ :create, :update ]

  # Evaluates active smart-collection rules against this asset immediately
  # after every create/update — metadata-only rules (see
  # {CollectionRule#metadata_only?}) don't need to wait for the async AI
  # embedding pipeline, so they route as soon as properties are saved.
  after_commit :trigger_smart_routing, on: [ :create, :update ]

  # Keeps the Duplicate Manager in sync whenever this asset is moved to (or
  # restored from) the Trash Bin — see {DuplicateGroup#recalculate_active_membership!}.
  # Hard deletion is handled separately via {DuplicateGroupAsset.cleanup_for_asset!}
  # and its own `after_destroy` safety net.
  after_commit :sync_duplicate_groups_membership, on: :update, if: :saved_change_to_deleted_at?

  after_initialize :set_property_defaults, if: :new_record?

  # Keeps the typed rights columns and the legacy +properties+ keys of the same
  # name in agreement — see {#normalise_rights}. Runs before validation so that
  # the vocabulary and date-format checks below see canonical values regardless
  # of which spelling the caller used.
  before_validation :normalise_rights

  # The "was this supplied?" flags describe one write, not the record. Left
  # standing, an explicit `usage_terms:` on one update would keep beating the
  # `properties` key on every later save of the same in-memory object.
  after_save :clear_rights_write_flags

  # ---------------------------------------------------------------------------
  # Public instance methods
  # ---------------------------------------------------------------------------

  # Returns the ActiveStorage file attachment on the currently active version.
  #
  # @return [ActiveStorage::Attached::One, nil]
  def current_file
    active_version&.file
  end

  # Whether this asset's licence window has closed.
  #
  # @param at [Time] the moment to judge against
  # @return [Boolean] +false+ when no expiry is recorded
  def license_expired?(at = Time.current)
    license_expires_at.present? && license_expires_at < at
  end

  # Whether the asset's usage terms permit distribution outside the
  # organisation *and* its licence is still current. Both must hold: a
  # royalty-free asset whose licence lapsed is no more distributable than an
  # internal-only one.
  #
  # This is the single question {Rights::DownloadPolicy} asks in Phase 10b;
  # it lives on the model so that reports and compliance scans give the same
  # answer as enforcement does.
  #
  # @param at [Time]
  # @return [Boolean]
  def externally_distributable?(at = Time.current)
    Rights::UsageTerms.externally_distributable?(usage_terms) && !license_expired?(at)
  end

  # The English label for the current usage terms. Translated labels belong
  # with the rights management UI, keyed on the code.
  #
  # @return [String]
  def usage_terms_label
    Rights::UsageTerms.label(usage_terms)
  end

  # Records *that* a term was supplied, not merely that it differed from the
  # one already stored.
  #
  # {#normalise_rights} has to decide which of two writers wins when a request
  # sets both the column and the +properties+ key. Asking +usage_terms_changed?+
  # looked equivalent but is not: assigning the value the record already holds
  # is not a change, so an explicit +usage_terms: "internal_only"+ on an asset
  # that was already internal-only lost to a +public_domain+ buried in the
  # metadata blob — the caller's clearest statement of intent was the one
  # discarded.
  def usage_terms=(value)
    @usage_terms_supplied = true
    super
  end

  # Parses before assigning, so that an unreadable date is *caught* rather than
  # swallowed.
  #
  # Active Record casts an unparseable string to +nil+ on the way into a
  # +datetime+ attribute. That silently discarded exactly the input this phase
  # exists to reject: +license_expires_at: "31/12/2026"+ arrived as +nil+,
  # nothing looked changed, and the request succeeded with the expiry quietly
  # dropped. Capturing the raw value here is what lets the validation below
  # report it.
  def license_expires_at=(value)
    @license_expiry_supplied = true
    @malformed_license_expiry_input =
      Rights::LicenseExpiry.malformed?(value) ? value : nil

    super(Rights::LicenseExpiry.parse(value))
  end

  # Returns the version number that should be assigned to the next new version.
  #
  # @return [Integer] max existing version number + 1, or 1 if no versions exist
  def next_version_number
    (asset_versions.maximum(:version_number) || 0) + 1
  end

  # Realistic usage counters for this asset, backed by the dedicated
  # {AssetUsageEvent} table rather than a bespoke integration or fabricated
  # numbers.
  #
  # These counts only reflect events that flow through our own app (viewer
  # opened, download initiated, link copied) — they will *not* capture
  # anonymous/hot-linked CDN hits that never touch Rails. For edge-level
  # bandwidth/view metrics, reconcile with the CDN provider's own reporting
  # API (see +app/services/cdn_adapters/+) in a scheduled job.
  #
  # @return [Hash{Symbol => Integer}]
  def usage_stats
    counts = asset_usage_events.group(:event_type).count

    {
      views:     counts["view"] || 0,
      downloads: counts["download"] || 0,
      shares:    counts["share"] || 0,
    }
  end

  # Whether this asset has been explicitly published (see {#publish!}).
  #
  # Deliberately independent of the {#status} lifecycle: an asset can be
  # +ready+ (fully processed) without being published, and — once this flag
  # ships — can remain published even if a later edit reverts +status+ to
  # +in_review+. Direct publish/unpublish is exposed via
  # {Api::V1::AssetsController#publish}/{Api::V1::AssetsController#unpublish};
  # the {WorkflowActionExecutor} "publish" step calls {#publish!} too, so both
  # paths converge on the same flag.
  #
  # @return [Boolean]
  def published?
    published_at.present?
  end

  # Marks the asset as published (sets {#published_at} to now).
  #
  # Cancels any still-pending scheduled publish/unpublish requests for this
  # asset — an explicit, immediate action always supersedes a queued one
  # rather than racing against it later (see {ScheduledPublishAction}).
  #
  # @return [void]
  def publish!
    update!(published_at: Time.current)
    scheduled_publish_actions.pending.update_all(status: ScheduledPublishAction.statuses[:cancelled]) # rubocop:disable Rails/SkipsModelValidations
  end

  # Reverts the asset to unpublished (clears {#published_at}).
  #
  # Cancels any still-pending scheduled publish/unpublish requests for this
  # asset, mirroring {#publish!}.
  #
  # @return [void]
  def unpublish!
    update!(published_at: nil)
    scheduled_publish_actions.pending.update_all(status: ScheduledPublishAction.statuses[:cancelled]) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  # Enqueues smart-collection routing after an asset is created or updated.
  # @api private
  def trigger_smart_routing
    SmartCollectionRouterWorker.perform_async(self.id)
  end

  # Recomputes membership for any pending {DuplicateGroup}s this asset
  # belongs to after it is soft-deleted or restored — see
  # {DuplicateGroup#recalculate_active_membership!}. Best-effort: a failure
  # here must never roll back or block the actual delete/restore.
  # @api private
  def sync_duplicate_groups_membership
    duplicate_group_assets.includes(:duplicate_group).find_each do |dga|
      dga.duplicate_group&.recalculate_active_membership!
    end
  rescue StandardError => e
    Rails.logger.warn("[Asset] Could not sync duplicate groups for asset ##{id}: #{e.message}")
  end

  # Publishes an +asset.needs_embedding+ event over the Redis pub/sub channel
  # so the AI gateway can generate and persist a new semantic vector.
  #
  # Failures are intentionally swallowed — a downed Redis must never roll back
  # or crash a metadata save.
  # @api private
  def broadcast_for_embedding
    return if properties.blank?

    payload = { event: "asset.needs_embedding", asset_uuid: self.id }.to_json
    redis   = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    redis.publish("ai_gateway_events", payload)
  rescue StandardError => e
    Rails.logger.warn("[Asset##{id}] embedding broadcast skipped: #{e.message}")
  end

  # Seeds the +properties+ JSONB column with safe default values on build.
  # @api private
  def set_property_defaults
    self.properties ||= {
      description:  "",
      usage_terms:  Rights::UsageTerms::DEFAULT,
      alt_text:     "",
      tags:         [],
    }
  end

  # Reconciles the typed rights columns with the +properties+ JSONB keys of the
  # same names, in both directions, before every validation.
  #
  # Both spellings have to keep working. The columns are the source of truth for
  # enforcement and reporting, but +properties+ is what the bulk metadata
  # editor, the migration importers and the XMP mapper write to, and what search
  # facets read. Rather than migrate a dozen call sites and hope none were
  # missed, whichever side was just written wins and the other is brought into
  # line — so an importer setting +properties["usage_terms"] = "Licensed"+ and an
  # API client setting +usage_terms = "rights_managed"+ both end up with the same
  # canonical value in both places.
  #
  # @api private
  def normalise_rights
    props = properties

    # jsonb accepts any valid JSON value, and an array or scalar genuinely does
    # turn up in this column — the metadata exporter has specs for tolerating
    # it. There is no key to keep in step with in that case, so the column is
    # normalised on its own rather than the save being blown up.
    unless props.is_a?(Hash)
      @malformed_license_expiry = @malformed_license_expiry_input
      self[:usage_terms] = Rights::UsageTerms.normalise(usage_terms)
      return
    end

    sync_usage_terms(props)
    sync_license_expiry(props)
  end

  # @api private
  def sync_usage_terms(properties)
    raw = if @usage_terms_supplied && usage_terms.present?
            usage_terms
    elsif properties.key?("usage_terms")
            properties["usage_terms"]
    else
            usage_terms
    end

    # An unrecognised term is kept verbatim alongside the canonical one instead
    # of being thrown away. It cannot be enforced on — the column falls back to
    # the restrictive default — but discarding what an importer actually read
    # from the file would destroy the only evidence of what the rights were
    # meant to say.
    if raw.present? && !Rights::UsageTerms.recognised?(raw)
      properties["usage_terms_raw"] = raw
    elsif raw.present?
      properties.delete("usage_terms_raw")
    end

    self[:usage_terms]        = Rights::UsageTerms.normalise(raw)
    properties["usage_terms"] = usage_terms
  end

  # @api private
  def sync_license_expiry(properties)
    @malformed_license_expiry = @malformed_license_expiry_input

    # A value was supplied and could not be read. The column has already been
    # left nil by the writer; the validation below turns this into a 422 rather
    # than a silently dropped expiry.
    return if @malformed_license_expiry.present?

    if @license_expiry_supplied
      properties["license_expires_at"] = Rights::LicenseExpiry.serialise(license_expires_at)
      return
    end

    return unless properties.key?("license_expires_at")

    raw = properties["license_expires_at"]

    if Rights::LicenseExpiry.malformed?(raw)
      # Left exactly as written, for the validation below to reject. The value
      # is neither guessed at nor quietly dropped: the save fails and the caller
      # is told which string could not be read. Historical junk that predates
      # this rule was preserved under a +_raw+ key by the backfill migration;
      # nothing new is allowed to join it.
      @malformed_license_expiry = raw
      self[:license_expires_at] = nil
      return
    end

    parsed = Rights::LicenseExpiry.parse(raw)
    self[:license_expires_at]        = parsed
    properties["license_expires_at"] = Rights::LicenseExpiry.serialise(parsed)
  end

  # @api private
  def clear_rights_write_flags
    @usage_terms_supplied           = false
    @license_expiry_supplied        = false
    @malformed_license_expiry_input = nil
  end

  # @api private
  def license_expiry_must_be_parseable
    return if @malformed_license_expiry.blank?

    errors.add(
      :license_expires_at,
      "must be an ISO 8601 date or timestamp (got #{@malformed_license_expiry.inspect})"
    )
  end
end
