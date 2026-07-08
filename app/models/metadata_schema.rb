class MetadataSchema < ApplicationRecord
  # ── Associations ──────────────────────────────────────────────────────────
  belongs_to :parent, class_name: "MetadataSchema", optional: true
  has_many   :children,
             class_name:  "MetadataSchema",
             foreign_key: :parent_id,
             dependent:   :destroy
  has_many   :folder_assignments,
             class_name:  "MetadataSchemaFolderAssignment",
             dependent:   :destroy

  # Root-to-root schema inheritance — distinct from `parent`/`children` above,
  # which encode the type/subtype MIME-resolution hierarchy. `inherits_from`
  # lets a custom root schema (e.g. "Copy of Product Images") pick another
  # root schema to inherit tabs from via a dropdown in the schema editor —
  # see {#resolved_tabs}.
  belongs_to :inherits_from, class_name: "MetadataSchema", optional: true
  has_many   :inheriting_schemas,
             class_name:  "MetadataSchema",
             foreign_key: :inherits_from_id,
             dependent:   :nullify

  # ── Validations ───────────────────────────────────────────────────────────
  validates :name,         presence: true
  validates :uuid,         presence: true, uniqueness: true
  validates :slug,         presence: true,
                           uniqueness: { conditions: -> { where(deleted_at: nil) },
                                         message: "must be unique among active schemas" }
  validates :level,        inclusion: { in: %w[root type subtype] }
  validate  :parent_required_for_non_root
  validate  :mime_segment_required_for_non_root
  validate  :inherits_from_must_be_root_level
  validate  :inherits_from_must_not_be_set_on_builtin_schema
  validate  :inherits_from_must_not_create_a_cycle

  # ── Callbacks ─────────────────────────────────────────────────────────────
  before_validation :set_uuid,       on: :create
  before_validation :generate_slug,  on: :create
  before_validation :coerce_tabs

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope :active,    -> { where(deleted_at: nil) }
  scope :roots,     -> { active.where(level: "root") }
  scope :builtin,   -> { active.where(is_builtin: true) }
  scope :custom,    -> { active.where(is_builtin: false) }

  # ── MIME Resolution ───────────────────────────────────────────────────────
  # Returns the most-specific schema for a given MIME string.
  # Pass root_schema_id: nil to use the global Default root.
  def self.resolve_for_mime(mime_string, root_schema_id: nil)
    mime_type, mime_subtype = mime_string.to_s.downcase.split("/")

    root =
      if root_schema_id.present?
        roots.find_by(id: root_schema_id)
      else
        roots.find_by(is_builtin: true, slug: "default")
      end

    return root unless root

    type_schema = root.children.active.find_by(mime_segment: mime_type)
    return root unless type_schema

    subtype_schema = type_schema.children.active.find_by(mime_segment: mime_subtype)
    subtype_schema || type_schema
  end

  # ── Hierarchy Helpers ─────────────────────────────────────────────────────
  def ancestors
    chain, node = [], self.parent
    while node
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  # Walks the `inherits_from` chain (oldest first) — distinct from `ancestors`
  # above, which walks the `parent`/MIME hierarchy chain instead.
  def inheritance_chain
    chain, node = [], self.inherits_from
    while node
      chain.unshift(node)
      node = node.inherits_from
    end
    chain
  end

  # Returns tabs with inherited fields merged from the MIME `parent` chain
  # AND the `inherits_from` root-to-root chain. Inherited tabs/fields carry
  # { "inherited" => true, "schema_name" => "<source schema>" } so the schema
  # editor can render them read-only (structural edits only make sense on the
  # source schema). Asset-level metadata *values* for inherited fields remain
  # editable — only a field's own explicit `read_only` flag locks its value.
  def resolved_tabs
    mime_inherited = ancestors.flat_map { |schema| inherited_tabs_for(schema) }
    schema_inherited = inheritance_chain.flat_map { |schema| inherited_tabs_for(schema) }

    own_tabs = (tabs || []).map { |t| t.merge("inherited" => false) }
    mime_inherited + schema_inherited + own_tabs
  end

  # Soft delete
  def soft_delete!
    update!(deleted_at: Time.current)
    children.active.find_each(&:soft_delete!)
  end

  private

  def inherited_tabs_for(schema)
    (schema.tabs || []).map do |tab|
      tab.merge(
        "inherited" => true,
        "schema_name" => schema.name,
        "fields" => (tab["fields"] || []).map { |f| f.merge("inherited" => true, "schema_name" => schema.name) }
      )
    end
  end

  def set_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def generate_slug
    return if name.blank? || slug.present?

    base = name.parameterize
    # Prepend parent slug for type/subtype to avoid collisions across trees
    if parent&.slug.present?
      base = "#{parent.slug}--#{base}"
    end

    self.slug = base
    counter   = 1
    while MetadataSchema.where(deleted_at: nil).where.not(id: id).exists?(slug: self.slug)
      self.slug = "#{base}-#{counter}"
      counter += 1
    end
  end

  def coerce_tabs
    self.tabs ||= []
  end

  def parent_required_for_non_root
    return if level == "root"
    errors.add(:parent_id, "must be present for type/subtype schemas") if parent_id.blank?
  end

  def mime_segment_required_for_non_root
    return if level == "root"
    errors.add(:mime_segment, "must be present for type/subtype schemas") if mime_segment.blank?
  end

  def inherits_from_must_be_root_level
    return if inherits_from_id.blank?

    errors.add(:inherits_from_id, "can only be set on root-level schemas") if level != "root"
    errors.add(:inherits_from_id, "must reference another root-level schema") if inherits_from && inherits_from.level != "root"
  end

  # Built-in root schemas (Default, Collection, Product Images, etc.) are
  # fixed OOTB starting points — they must never inherit from each other.
  # Only custom (non-builtin) schemas may inherit from a root schema
  # (built-in or custom).
  def inherits_from_must_not_be_set_on_builtin_schema
    return if inherits_from_id.blank?

    errors.add(:inherits_from_id, "cannot be set on a built-in schema") if is_builtin?
  end

  def inherits_from_must_not_create_a_cycle
    return if inherits_from_id.blank?

    if inherits_from_id == id
      errors.add(:inherits_from_id, "cannot inherit from itself")
      return
    end

    visited = Set.new
    node = inherits_from
    while node
      if node.id == id || visited.include?(node.id)
        errors.add(:inherits_from_id, "would create a circular inheritance chain")
        break
      end
      visited << node.id
      node = node.inherits_from
    end
  end
end
