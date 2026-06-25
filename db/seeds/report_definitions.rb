# ─── Report Definitions Seed ──────────────────────────────────────────────────
# Creates the 10 built-in ReportDefinition records.
# Safe to re-run (find_or_create_by prevents duplicates).
#
# Usage: rails db:seed:reports
# Or:    rails db:seed   (if this file is required from db/seeds.rb)

REPORT_DEFINITIONS = [
  {
    name:        'Asset Library Summary',
    report_type: 'asset_library',
    description: 'Overview of all assets by status, content type, folder, and user. The core DAM health check.',
    active:      true,
    query_config: {
      selects: %w[uuid title status content_type folder user created_at size],
      group_by: 'status',
    },
  },
  {
    name:        'Workflow Compliance Report',
    report_type: 'workflow_compliance',
    description: 'Approval rates, average review time, rejection reasons, and SLA adherence by workflow type.',
    active:      true,
    query_config: {
      model: 'WorkflowInstance',
      selects: %w[workflow_name asset_title status started_at completed_at duration_hours],
    },
  },
  {
    name:        'Storage Usage Report',
    report_type: 'storage_usage',
    description: 'Storage consumed by content type, folder, and user. Identifies storage waste from large unused assets.',
    active:      true,
    query_config: {
      aggregation: 'SUM(size)',
      group_by: %w[content_type folder user],
    },
  },
  {
    name:        'User Activity Report',
    report_type: 'user_activity',
    description: 'Upload frequency, workflow actions, login history, and permission changes per user.',
    active:      true,
    query_config: {
      model: 'AuditLog',
      selects: %w[user_email action count last_action_at],
    },
  },
  {
    name:        'AI Coverage & Enrichment Report',
    report_type: 'ai_coverage',
    description: 'Vector embedding coverage, assets missing alt_text or tags, semantic search query volume, and AI enrichment ROI.',
    active:      true,
    query_config: {
      join: 'asset_embeddings',
      selects: %w[uuid title embedding_status model_name enrichment_date],
    },
  },
  {
    name:        'Duplicate Detection Report',
    report_type: 'duplicates',
    description: 'All duplicate assets detected via SHA-256 checksums — both live duplicates and migration-blocked entries. Quantifies storage savings.',
    active:      true,
    query_config: {
      checksum_match: true,
      include_migration: true,
    },
  },
  {
    name:        'License Expiry Forecast',
    report_type: 'license_expiry',
    description: 'Assets with license_expires_at within the next 30, 60, and 90 days. Essential for campaign risk management.',
    active:      true,
    query_config: {
      filter: "properties->>'license_expires_at' IS NOT NULL",
      sort: "license_expires_at ASC",
    },
  },
  {
    name:        'Collection & Smart Routing Report',
    report_type: 'collections',
    description: 'Asset distribution across collections, AI vs manual routing ratio, compliance violations, and expiry status.',
    active:      true,
    query_config: {
      model: 'Collection',
      include_smart_rules: true,
    },
  },
  {
    name:        'Audit Trail Report',
    report_type: 'audit_trail',
    description: 'Full immutable log of all system actions — uploads, edits, deletes, approvals, and permission changes with IP and user agent.',
    active:      true,
    query_config: {
      model: 'AuditLog',
      selects: %w[user_email action auditable_type changes_data ip_address created_at],
    },
  },
  {
    name:        'Migration Batch Summary',
    report_type: 'migration',
    description: 'Per-batch migration results: assets committed, duplicates blocked, errors, AI enrichment coverage, and storage cost savings.',
    active:      true,
    query_config: {
      model: 'IngestionBatch',
      selects: %w[name source_type status committed_count duplicate_count error_count completed_at],
    },
  },
].freeze

REPORT_DEFINITIONS.each do |attrs|
  config = attrs.delete(:description) # description isn't a DB column — store in query_config
  report = ReportDefinition.find_or_initialize_by(name: attrs[:name])
  report.assign_attributes(attrs)
  report.query_config = (attrs[:query_config] || {}).merge('description' => config)
  report.active = true
  report.save!
  Rails.logger.debug "✅ ReportDefinition: #{report.name}"
end
