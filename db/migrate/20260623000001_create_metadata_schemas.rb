class CreateMetadataSchemas < ActiveRecord::Migration[8.1]
  def up
    create_table :metadata_schemas do |t|
      t.string   :uuid,        null: false
      t.string   :name,        null: false
      t.string   :slug,        null: false
      t.text     :description
      t.string   :level,       null: false, default: 'root'
      t.bigint   :parent_id
      t.string   :mime_segment
      t.boolean  :is_builtin,  null: false, default: false
      t.jsonb    :tabs,        null: false, default: []
      t.jsonb    :properties,  null: false, default: {}
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :metadata_schemas, :uuid,       unique: true
    add_index :metadata_schemas, :slug,       unique: true, where: "deleted_at IS NULL"
    add_index :metadata_schemas, :parent_id
    add_index :metadata_schemas, :level
    add_index :metadata_schemas, :deleted_at
    add_index :metadata_schemas, :is_builtin
    add_index :metadata_schemas, %i[parent_id mime_segment],
              unique: true,
              where: "deleted_at IS NULL AND mime_segment IS NOT NULL",
              name: "idx_metadata_schemas_parent_mime_unique"
    add_foreign_key :metadata_schemas, :metadata_schemas, column: :parent_id

    create_table :metadata_schema_folder_assignments do |t|
      t.bigint :metadata_schema_id, null: false
      t.string :folder_id,          null: false
      t.timestamps
    end

    add_index :metadata_schema_folder_assignments,
              %i[metadata_schema_id folder_id], unique: true, name: "idx_schema_folder_unique"
    add_index :metadata_schema_folder_assignments, :folder_id,
              name: "idx_schema_folder_on_folder_id"
    add_foreign_key :metadata_schema_folder_assignments, :metadata_schemas

    seed_default_schemas!
  end

  def down
    drop_table :metadata_schema_folder_assignments
    drop_table :metadata_schemas
  end

  private

  # ── Field builder ─────────────────────────────────────────────────────────
  def f(type, label, property, position, required: false, read_only: false, options: nil)
    o = {
      "id"              => SecureRandom.uuid,
      "field_type"      => type,
      "label"           => label,
      "map_to_property" => property,
      "position"        => position,
      "required"        => required,
      "read_only"       => read_only,
      "rules"           => {}
    }
    o["options"] = options if options
    o
  end

  # ── Shared tab builders ───────────────────────────────────────────────────
  def basic_tab
    { "id" => "tab-basic", "name" => "Basic", "position" => 0,
      "fields" => [
        f("text",     "Title",        "dc:title",       0, required: true),
        f("textarea", "Description",  "dc:description", 1),
        f("text",     "Creator",      "dc:creator",     2),
        f("date",     "Date Created", "dc:date",        3),
        f("text",     "Rights",       "dc:rights",      4)
      ] }
  end

  def iptc_tab
    { "id" => "tab-iptc", "name" => "IPTC", "position" => 1,
      "fields" => [
        f("text",     "Headline", "Iptc4xmpCore:Headline",    0),
        f("text",     "Byline",   "Iptc4xmpCore:Byline",      1),
        f("text",     "Credit",   "Iptc4xmpCore:CreditLine",  2),
        f("text",     "Source",   "Iptc4xmpCore:Source",      3),
        f("textarea", "Caption",  "Iptc4xmpCore:Description", 4),
        f("text",     "City",     "Iptc4xmpCore:City",        5),
        f("text",     "Country",  "Iptc4xmpCore:CountryName", 6),
        f("tags",     "Keywords", "Iptc4xmpCore:SubjectCode", 7)
      ] }
  end

  def camera_tab
    { "id" => "tab-camera", "name" => "Camera", "position" => 2,
      "fields" => [
        f("text", "Camera Make",   "exif:Make",              0, read_only: true),
        f("text", "Camera Model",  "exif:Model",             1, read_only: true),
        f("text", "Focal Length",  "exif:FocalLength",       2, read_only: true),
        f("text", "Aperture",      "exif:ApertureValue",     3, read_only: true),
        f("text", "ISO",           "exif:ISOSpeedRatings",   4, read_only: true),
        f("text", "Shutter Speed", "exif:ShutterSpeedValue", 5, read_only: true)
      ] }
  end

  # ── Schema row insertion ──────────────────────────────────────────────────
  def insert_schema!(name:, slug:, description: nil, level:, parent_id: nil,
                     mime_segment: nil, is_builtin: false, tabs: [])
    now  = Time.current.utc
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL)
      INSERT INTO metadata_schemas
        (uuid, name, slug, description, level, parent_id, mime_segment,
         is_builtin, tabs, properties, created_at, updated_at)
      VALUES (
        '#{SecureRandom.uuid}',
        #{conn.quote(name)},
        #{conn.quote(slug)},
        #{description ? conn.quote(description) : 'NULL'},
        #{conn.quote(level)},
        #{parent_id.presence || 'NULL'},
        #{mime_segment ? conn.quote(mime_segment) : 'NULL'},
        #{is_builtin},
        #{conn.quote(tabs.to_json)},
        '{}', '#{now}', '#{now}'
      )
    SQL
    conn.execute("SELECT id FROM metadata_schemas WHERE slug = #{conn.quote(slug)} LIMIT 1")
        .first["id"].to_i
  end

  # ── Seed built-in schemas ─────────────────────────────────────────────────
  def seed_default_schemas!
    # ── Root: Default ────────────────────────────────────────────────────
    default_id = insert_schema!(
      name: "Default", slug: "default", level: "root", is_builtin: true,
      description: "Global fallback schema. Used when no other schema resolves.",
      tabs: [basic_tab, iptc_tab, camera_tab]
    )

    image_id = insert_schema!(
      name: "Image", slug: "default--image", level: "type",
      parent_id: default_id, mime_segment: "image", is_builtin: true,
      description: "Applies to all image/* assets under the Default root.", tabs: []
    )

    %w[jpeg png tiff gif webp].each do |sub|
      insert_schema!(
        name: sub.upcase, level: "subtype",
        slug: "default--image--#{sub}",
        parent_id: image_id, mime_segment: sub, is_builtin: true,
        description: "Schema for image/#{sub} assets.", tabs: []
      )
    end

    app_id = insert_schema!(
      name: "Application", slug: "default--application", level: "type",
      parent_id: default_id, mime_segment: "application", is_builtin: true,
      description: "Applies to all application/* assets under the Default root.", tabs: []
    )

    { "pdf" => "PDF", "zip" => "ZIP Archive" }.each do |ms, label|
      insert_schema!(
        name: label, level: "subtype",
        slug: "default--application--#{ms}",
        parent_id: app_id, mime_segment: ms, is_builtin: true, tabs: []
      )
    end

    insert_schema!(
      name: "Video", slug: "default--video", level: "type",
      parent_id: default_id, mime_segment: "video", is_builtin: true,
      description: "Applies to all video/* assets under the Default root.", tabs: []
    )

    # ── Root: Collection ────────────────────────────────────────────────
    insert_schema!(
      name: "Collection", slug: "collection", level: "root", is_builtin: true,
      description: "Default schema applied to asset collections.",
      tabs: [
        { "id" => "tab-col", "name" => "Basic", "position" => 0,
          "fields" => [
            f("text",     "Collection Name", "dam:collectionName", 0, required: true),
            f("textarea", "Summary",         "dam:collectionDesc", 1),
            f("tags",     "Tags",            "dam:tags",           2),
            f("select",   "Visibility",      "dam:visibility",     3,
              options: [{ "value" => "public",     "label" => "Public" },
                        { "value" => "internal",   "label" => "Internal" },
                        { "value" => "restricted", "label" => "Restricted" }])
          ] }
      ]
    )

    # ── Root: Product Images ────────────────────────────────────────────
    insert_schema!(
      name: "Product Images", slug: "product-images", level: "root", is_builtin: true,
      description: "Schema for product photography assets.",
      tabs: [
        basic_tab,
        { "id" => "tab-prod", "name" => "Product", "position" => 1,
          "fields" => [
            f("text",   "SKU",            "dam:sku",         0, required: true),
            f("text",   "Product Name",   "dam:productName", 1),
            f("text",   "Brand",          "dam:brand",       2),
            f("text",   "Color",          "dam:color",       3),
            f("text",   "Size / Variant", "dam:variant",     4),
            f("select", "Shot Type",      "dam:shotType",    5,
              options: [{ "value" => "hero",      "label" => "Hero" },
                        { "value" => "lifestyle", "label" => "Lifestyle" },
                        { "value" => "detail",    "label" => "Detail" },
                        { "value" => "swatch",    "label" => "Swatch" }]),
            f("text",   "Campaign",       "dam:campaign",    6),
            f("tags",   "Tags",           "dam:tags",        7)
          ] }
      ]
    )
  end
end
