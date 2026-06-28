# frozen_string_literal: true

module Ai
  # Declarative registry of the AI batch tasks and target datasets available
  # on the "AI Batch Tasks" screen (/ai/tasks).
  #
  # This is the single source of truth that powers:
  #   * the data-driven task/dataset selectors in the React UI
  #     (GET /api/v1/ai_batch_jobs/task_types)
  #   * AiBatchJob validation (task_type / target_scope inclusion)
  #   * AiBatchJobWorker target resolution
  #
  # == Adding a future AI task
  #
  # To expose a new AI capability, add one TASKS entry below.  No migration,
  # controller, or model change is required — the UI and the gateway payload
  # pick it up automatically.  The gateway must implement the matching
  # +gateway_capability+ handler (see docs/ai-gateway-prompt.md).
  #
  # @example Register a new task
  #   Task.new(
  #     key:                "nsfw_moderation",
  #     label:              "NSFW Moderation",
  #     description:        "Flag explicit or unsafe imagery for review.",
  #     cost_tier:          "medium",
  #     default_tools:      %w[VisionModerator QuarantineAction],
  #     gateway_capability: "moderation.nsfw",
  #   )
  module BatchTaskRegistry
    # A single AI task descriptor.
    Task = Struct.new(
      :key, :label, :description, :cost_tier, :default_tools, :gateway_capability,
      keyword_init: true,
    )

    # A single target-dataset descriptor.  +resolver+ is a callable returning an
    # ActiveRecord::Relation of the assets the task should run against.
    Scope = Struct.new(:key, :label, :description, :resolver, keyword_init: true)

    COST_TIERS = %w[low medium high].freeze

    # -- AI tasks ---------------------------------------------------------------
    TASKS = [
      Task.new(
        key:                "metadata_extraction",
        label:              "Metadata Extraction",
        description:        "Extract structured metadata (title, description, keywords) from each asset.",
        cost_tier:          "low",
        default_tools:      %w[VisualContextExtractor JsonSchemaValidator],
        gateway_capability: "metadata.extract",
      ),
      Task.new(
        key:                "seo_enrichment",
        label:              "SEO Enrichment",
        description:        "Generate SEO-friendly tags, alt text and captions.",
        cost_tier:          "low",
        default_tools:      %w[SEOTaxonomyMapper AltTextWriter],
        gateway_capability: "metadata.seo",
      ),
      Task.new(
        key:                "visual_context",
        label:              "Deep Visual Context",
        description:        "Run high-fidelity vision analysis to describe scene, objects and mood.",
        cost_tier:          "high",
        default_tools:      %w[VisualContextExtractor SceneGraphBuilder],
        gateway_capability: "vision.describe",
      ),
      Task.new(
        key:                "compliance_check",
        label:              "Copyright / Compliance Check",
        description:        "Detect watermarks, stock origins and licensing risks.",
        cost_tier:          "medium",
        default_tools:      %w[WatermarkDetector QuarantineAction],
        gateway_capability: "compliance.audit",
      ),
      Task.new(
        key:                "embedding_backfill",
        label:              "Embedding Backfill",
        description:        "Generate semantic vectors so assets become searchable in the Copilot.",
        cost_tier:          "low",
        default_tools:      %w[EmbeddingGenerator],
        gateway_capability: "embedding.generate",
      ),

      # ── Content Provenance / C2PA tasks ─────────────────────────────────────

      Task.new(
        key:                "c2pa_verify",
        label:              "C2PA Verification",
        description:        "Parse and cryptographically verify C2PA manifests. Flags AI-generated and AI-modified assets.",
        cost_tier:          "low",
        default_tools:      %w[C2PAParser TrustStoreVerifier],
        gateway_capability: "c2pa.verify",
      ),
      Task.new(
        key:                "c2pa_sign",
        label:              "C2PA Signing",
        description:        "Embed a new C2PA manifest signed with the configured DAM identity.",
        cost_tier:          "medium",
        default_tools:      %w[C2PASigner ManifestBuilder],
        gateway_capability: "c2pa.sign",
      ),
      Task.new(
        key:                "ai_disclosure_audit",
        label:              "AI Disclosure Audit",
        description:        "Identify assets that are AI-generated or AI-modified but lack required disclosure in their C2PA manifest.",
        cost_tier:          "low",
        default_tools:      %w[AIDisclosureChecker C2PAParser],
        gateway_capability: "disclosure.audit",
      ),
    ].freeze

    # -- Target datasets --------------------------------------------------------
    SCOPES = [
      Scope.new(
        key:         "all_assets",
        label:       "All Assets",
        description: "Every active asset in the library.",
        resolver:    -> { Asset.active },
      ),
      Scope.new(
        key:         "all_images",
        label:       "All Images",
        description: "Active assets with an image/* content type.",
        resolver:    -> { Asset.active.where("properties->>'content_type' ILIKE 'image/%'") },
      ),
      Scope.new(
        key:         "missing_metadata",
        label:       "Assets Missing a Description",
        description: "Active assets with no description property.",
        resolver:    -> {
          Asset.active.where("properties->>'description' IS NULL OR properties->>'description' = ''")
        },
      ),
      Scope.new(
        key:         "missing_tags",
        label:       "Assets With No Tags",
        description: "Active assets with an empty or missing tags property.",
        resolver:    -> {
          Asset.active.where("properties->'tags' IS NULL OR jsonb_array_length(COALESCE(properties->'tags', '[]'::jsonb)) = 0")
        },
      ),
      Scope.new(
        key:         "missing_embeddings",
        label:       "Assets Without Embeddings",
        description: "Active assets that have never been vectorised for semantic search.",
        resolver:    -> { Asset.active.where.missing(:asset_embedding) },
      ),

      # ── C2PA / Provenance scopes ─────────────────────────────────────────────

      Scope.new(
        key:         "unverified_assets",
        label:       "Assets Without C2PA Verification",
        description: "Active assets that have no provenance record or have never been C2PA-verified.",
        resolver:    -> {
          verified_ids = AssetProvenanceRecord.where.not(manifest_status: "unchecked").select(:asset_id)
          Asset.active.where.not(id: verified_ids)
        },
      ),
      Scope.new(
        key:         "invalid_manifests",
        label:       "Assets With Invalid Manifests",
        description: "Active assets whose C2PA manifests failed cryptographic verification.",
        resolver:    -> {
          Asset.active.joins(:asset_provenance_record)
               .where(asset_provenance_records: { manifest_status: "invalid" })
        },
      ),
      Scope.new(
        key:         "ai_modified_assets",
        label:       "AI-Modified Assets",
        description: "Active assets flagged as AI-generated or AI-modified via their C2PA manifest.",
        resolver:    -> {
          Asset.active.joins(:asset_provenance_record)
               .where(asset_provenance_records: { is_ai_modified: true })
        },
      ),
      Scope.new(
        key:         "unsigned_assets",
        label:       "Assets Not Signed by DAM",
        description: "Active assets that have not yet been signed with the DAM's own C2PA identity.",
        resolver:    -> {
          signed_ids = AssetProvenanceRecord.where(manifest_status: "signed").select(:asset_id)
          Asset.active.where.not(id: signed_ids)
        },
      ),
    ].freeze

    module_function

    # @return [Array<Task>]
    def tasks
      TASKS
    end

    # @return [Array<Scope>]
    def scopes
      SCOPES
    end

    # @return [Array<String>]
    def task_keys
      TASKS.map(&:key)
    end

    # @return [Array<String>]
    def scope_keys
      SCOPES.map(&:key)
    end

    # @param key [String]
    # @return [Task, nil]
    def task(key)
      TASKS.find { |t| t.key == key.to_s }
    end

    # @param key [String]
    # @return [Scope, nil]
    def scope(key)
      SCOPES.find { |s| s.key == key.to_s }
    end

    # Resolves the target dataset for a scope key into an ActiveRecord relation.
    #
    # @param key [String]
    # @return [ActiveRecord::Relation] empty relation when the key is unknown
    def resolve_targets(key)
      found = scope(key)
      return Asset.none unless found

      found.resolver.call
    end

    # Serialisable metadata for the front-end form.
    #
    # @return [Hash]
    def as_json_meta
      {
        tasks: TASKS.map do |t|
          {
            key:                t.key,
            label:              t.label,
            description:        t.description,
            cost_tier:          t.cost_tier,
            default_tools:      t.default_tools,
            gateway_capability: t.gateway_capability,
          }
        end,
        scopes: SCOPES.map do |s|
          { key: s.key, label: s.label, description: s.description }
        end,
      }
    end
  end
end
