class MetadataSchema < ApplicationRecord
  # ── Associations ──────────────────────────────────────────────────────────
  belongs_to :parent, class_name: 'MetadataSchema', optional: true
  has_many   :children,
             class_name:  'MetadataSchema',
             foreign_key: :parent_id,
             dependent:   :destroy
  has_many   :folder_assignments,
             class_name:  'MetadataSchemaFolderAssignment',
             dependent:   :destroy

  # ── Validations ───────────────────────────────────────────────────────────
  validates :name,         presence: true
  validates :uuid,         presence: true, uniqueness: true
  validates :slug,         presence: true,
                           uniqueness: { conditions: -> { where(deleted_at: nil) },
                                         message: 'must be unique among active schemas' }
  validates :level,        inclusion: { in: %w[root type subtype] }
  validate  :parent_required_for_non_root
  validate  :mime_segment_required_for_non_root

  # ── Callbacks ─────────────────────────────────────────────────────────────
  before_validation :set_uuid,       on: :create
  before_validation :generate_slug,  on: :create
  before_validation :coerce_tabs

  # ── Scopes ────────────────────────────────────────────────────────────────
  scope :active,    -> { where(deleted_at: nil) }
  scope :roots,     -> { active.where(level: 'root') }
  scope :builtin,   -> { active.where(is_builtin: true) }
  scope :custom,    -> { active.where(is_builtin: false) }

  # ── MIME Resolution ───────────────────────────────────────────────────────
  # Returns the most-specific schema for a given MIME string.
  # Pass root_schema_id: nil to use the global Default root.
  def self.resolve_for_mime(mime_string, root_schema_id: nil)
    mime_type, mime_subtype = mime_string.to_s.downcase.split('/')

    root =
      if root_schema_id.present?
        roots.find_by(id: root_schema_id)
      else
        roots.find_by(is_builtin: true, slug: 'default')
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

  # Returns tabs with inherited fields merged from the parent chain.
  # Inherited tabs/fields carry { "inherited" => true } for UI read-only treatment.
  def resolved_tabs
    inherited_tabs = ancestors.flat_map do |schema|
      (schema.tabs || []).map do |tab|
        tab.merge(
          'inherited' => true,
          'schema_name' => schema.name,
          'fields' => (tab['fields'] || []).map { |f| f.merge('inherited' => true) }
        )
      end
    end

    own_tabs = (tabs || []).map { |t| t.merge('inherited' => false) }
    inherited_tabs + own_tabs
  end

  # Soft delete
  def soft_delete!
    update!(deleted_at: Time.current)
    children.active.find_each(&:soft_delete!)
  end

  private

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
    return if level == 'root'
    errors.add(:parent_id, 'must be present for type/subtype schemas') if parent_id.blank?
  end

  def mime_segment_required_for_non_root
    return if level == 'root'
    errors.add(:mime_segment, 'must be present for type/subtype schemas') if mime_segment.blank?
  end
end

