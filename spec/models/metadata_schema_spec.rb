# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetadataSchema, type: :model do
  # ── Factories ──────────────────────────────────────────────────────────────
  let(:root_schema)    { create(:metadata_schema, :root) }
  let(:type_schema)    { create(:metadata_schema, :type_level, parent: root_schema, mime_segment: 'image') }
  let(:subtype_schema) { create(:metadata_schema, :subtype_level, parent: type_schema, mime_segment: 'jpeg') }

  # ── Validations ────────────────────────────────────────────────────────────
  describe 'validations' do
    it 'is valid with valid root attributes' do
      expect(build(:metadata_schema, :root)).to be_valid
    end

    it 'requires a name' do
      schema = build(:metadata_schema, name: '')
      expect(schema).not_to be_valid
      expect(schema.errors[:name]).to include("can't be blank")
    end

    it 'requires a valid level' do
      schema = build(:metadata_schema, level: 'invalid')
      expect(schema).not_to be_valid
    end

    it 'requires parent_id for type schemas' do
      schema = build(:metadata_schema, level: 'type', parent_id: nil, mime_segment: 'image')
      expect(schema).not_to be_valid
      expect(schema.errors[:parent_id]).to be_present
    end

    it 'requires mime_segment for type schemas' do
      schema = build(:metadata_schema, level: 'type', parent: root_schema, mime_segment: nil)
      expect(schema).not_to be_valid
      expect(schema.errors[:mime_segment]).to be_present
    end

    it 'does not require mime_segment for root schemas' do
      schema = build(:metadata_schema, level: 'root', mime_segment: nil)
      expect(schema).to be_valid
    end

    it 'allows inherits_from_id on a root schema pointing at another root schema' do
      other = create(:metadata_schema, :root)
      schema = build(:metadata_schema, :root, inherits_from: other)
      expect(schema).to be_valid
    end

    it 'rejects inherits_from_id on a non-root schema' do
      other = create(:metadata_schema, :root)
      schema = build(:metadata_schema, :type_level, parent: root_schema, inherits_from: other)
      expect(schema).not_to be_valid
      expect(schema.errors[:inherits_from_id]).to include("can only be set on root-level schemas")
    end

    it 'rejects inherits_from pointing at a non-root schema' do
      schema = build(:metadata_schema, :root, inherits_from: type_schema)
      expect(schema).not_to be_valid
      expect(schema.errors[:inherits_from_id]).to include("must reference another root-level schema")
    end

    it 'rejects inherits_from_id being set on a built-in schema (built-ins must not inherit from each other)' do
      default_schema     = create(:metadata_schema, :root, :builtin, name: "Default")
      collection_schema  = build(:metadata_schema, :root, :builtin, name: "Collection", inherits_from: default_schema)
      expect(collection_schema).not_to be_valid
      expect(collection_schema.errors[:inherits_from_id]).to include("cannot be set on a built-in schema")
    end

    it 'still allows a custom (non-builtin) schema to inherit from a built-in schema' do
      default_schema = create(:metadata_schema, :root, :builtin, name: "Default")
      custom_schema  = build(:metadata_schema, :root, name: "My Custom Schema", inherits_from: default_schema)
      expect(custom_schema).to be_valid
    end

    it 'rejects self-referential inheritance' do
      schema = create(:metadata_schema, :root)
      schema.inherits_from_id = schema.id
      expect(schema).not_to be_valid
      expect(schema.errors[:inherits_from_id]).to include("cannot inherit from itself")
    end

    it 'rejects circular inheritance chains' do
      a = create(:metadata_schema, :root)
      b = create(:metadata_schema, :root, inherits_from: a)
      a.inherits_from = b
      expect(a).not_to be_valid
      expect(a.errors[:inherits_from_id]).to include("would create a circular inheritance chain")
    end
  end

  # ── UUID / Slug callbacks ──────────────────────────────────────────────────
  describe 'auto-generated attributes' do
    it 'generates a UUID on create' do
      schema = create(:metadata_schema, :root)
      expect(schema.uuid).to be_present
      expect(schema.uuid).to match(/\A[0-9a-f\-]{36}\z/)
    end

    it 'generates a slug from the name on create' do
      schema = create(:metadata_schema, :root, name: 'My Custom Schema', slug: nil)
      expect(schema.slug).to eq('my-custom-schema')
    end

    it 'generates a unique slug when collision exists' do
      create(:metadata_schema, :root, name: 'Duplicate', slug: 'duplicate')
      schema2 = create(:metadata_schema, :root, name: 'Duplicate', slug: nil)
      expect(schema2.slug).to eq('duplicate-1')
    end
  end

  # ── Scopes ─────────────────────────────────────────────────────────────────
  describe 'scopes' do
    before { root_schema }

    it '.active excludes soft-deleted schemas' do
      root_schema.update!(deleted_at: Time.current)
      expect(MetadataSchema.active).not_to include(root_schema)
    end

    it '.roots returns only root-level schemas' do
      type_schema
      expect(MetadataSchema.roots).to include(root_schema)
      expect(MetadataSchema.roots).not_to include(type_schema)
    end
  end

  # ── MIME resolution ────────────────────────────────────────────────────────
  describe '.resolve_for_mime' do
    before do
      root_schema
      type_schema
      subtype_schema
    end

    it 'resolves to the subtype schema for an exact MIME match' do
      allow(MetadataSchema).to receive(:roots).and_call_original
      # Temporarily make root_schema the builtin default
      root_schema.update!(is_builtin: true, slug: 'default')

      result = MetadataSchema.resolve_for_mime('image/jpeg')
      expect(result).to eq(subtype_schema)
    end

    it 'falls back to the type schema when subtype is not found' do
      root_schema.update!(is_builtin: true, slug: 'default')

      result = MetadataSchema.resolve_for_mime('image/png')
      expect(result).to eq(type_schema)
    end

    it 'falls back to the root schema when neither type nor subtype match' do
      root_schema.update!(is_builtin: true, slug: 'default')

      result = MetadataSchema.resolve_for_mime('audio/mpeg')
      expect(result).to eq(root_schema)
    end

    it 'accepts a root_schema_id override' do
      custom_root = create(:metadata_schema, :root)
      result = MetadataSchema.resolve_for_mime('image/jpeg', root_schema_id: custom_root.id)
      # custom_root has no children, so it returns root
      expect(result).to eq(custom_root)
    end
  end

  # ── resolved_tabs ──────────────────────────────────────────────────────────
  describe '#resolved_tabs' do
    let(:root_with_tabs) {
      create(:metadata_schema, :root, :with_basic_tab)
    }

    it 'returns own tabs for a root schema' do
      tabs = root_with_tabs.resolved_tabs
      expect(tabs.map { |t| t['name'] }).to include('Basic')
      expect(tabs.none? { |t| t['inherited'] }).to be true
    end

    it 'marks inherited tabs on child schemas' do
      child = create(:metadata_schema, level: 'type', parent: root_with_tabs,
                     mime_segment: 'image', tabs: [])
      tabs = child.resolved_tabs
      inherited = tabs.select { |t| t['inherited'] }
      expect(inherited.map { |t| t['name'] }).to include('Basic')
    end

    it 'merges tabs from the inherits_from root-to-root chain' do
      custom = create(:metadata_schema, :root, inherits_from: root_with_tabs, tabs: [])
      tabs = custom.resolved_tabs
      inherited = tabs.select { |t| t['inherited'] }
      expect(inherited.map { |t| t['name'] }).to include('Basic')
      expect(inherited.first['schema_name']).to eq(root_with_tabs.name)
    end

    it 'tags each inherited field with the source schema_name (asset-viewer values stay editable; only read_only fields lock)' do
      child = create(:metadata_schema, level: 'type', parent: root_with_tabs,
                     mime_segment: 'image', tabs: [])
      tabs = child.resolved_tabs
      inherited_fields = tabs.select { |t| t['inherited'] }.flat_map { |t| t['fields'] }
      expect(inherited_fields).not_to be_empty
      inherited_fields.each do |f|
        expect(f['inherited']).to be true
        expect(f['schema_name']).to eq(root_with_tabs.name)
      end
    end

    it 'includes own tabs alongside inherited ones' do
      custom = create(:metadata_schema, :root, :with_basic_tab, inherits_from: root_with_tabs)
      tabs = custom.resolved_tabs
      expect(tabs.count { |t| t['inherited'] }).to eq(1)
      expect(tabs.count { |t| !t['inherited'] }).to eq(1)
    end
  end

  # ── inheritance_chain ────────────────────────────────────────────────────────
  describe '#inheritance_chain' do
    it 'walks the inherits_from chain oldest-first' do
      grandparent = create(:metadata_schema, :root)
      parent      = create(:metadata_schema, :root, inherits_from: grandparent)
      child       = create(:metadata_schema, :root, inherits_from: parent)

      expect(child.inheritance_chain).to eq([ grandparent, parent ])
    end

    it 'returns an empty array when there is no inherits_from' do
      expect(root_schema.inheritance_chain).to eq([])
    end
  end

  # ── soft_delete! ───────────────────────────────────────────────────────────
  describe '#soft_delete!' do
    it 'sets deleted_at on the schema and all its children' do
      root_schema
      type_schema

      root_schema.soft_delete!

      expect(root_schema.reload.deleted_at).to be_present
      expect(type_schema.reload.deleted_at).to be_present
    end
  end
end
