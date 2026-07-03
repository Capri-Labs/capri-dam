# Ensures the built-in {MetadataSchema} trees ("Default" by-MIME-type,
# "Collection", and "Product Images") exist.
#
# == Why this exists
#
# These built-in schemas were originally only created as one-off data inside
# +db/migrate/20260623000001_create_metadata_schemas.rb+'s +up+ method. That
# works when a database is provisioned via `rails db:migrate` from empty, but
# it is **silently skipped** when a database is instead provisioned via
# `rails db:schema:load` / `rails db:prepare` against an existing
# +db/schema.rb+ (the common path for fresh checkouts, CI, and some
# production bootstrap scripts) — that path loads the table *structure* only
# and stamps `schema_migrations` directly, without ever executing the
# migration's Ruby code. The result: a "fresh" database has the
# `metadata_schemas` table but zero rows in it, and the Metadata Schemas admin
# screen appears empty even though nothing was ever "deleted".
#
# This seeder is the idempotent, re-runnable fix: it is safe to call from
# +db/seeds.rb+ (every environment, every time) and will:
#
#   * create any built-in schema that is completely missing,
#   * restore (un-soft-delete) any built-in schema that was soft-deleted,
#   * leave untouched any schema that already exists and is active, so it
#     never clobbers customisations an admin has made to a built-in schema.
#
# @see MetadataSchema
class MetadataSchemaSeeder
  ASSET_TYPE_OPTIONS = [
    { "value" => "FR01", "label" => "FR01 — Front (Primary)" },
    { "value" => "FR02", "label" => "FR02 — Front (Alt)" },
    { "value" => "FR03", "label" => "FR03 — Front Detail" },
    { "value" => "BK01", "label" => "BK01 — Back (Primary)" },
    { "value" => "BK02", "label" => "BK02 — Back (Alt)" },
    { "value" => "SD01", "label" => "SD01 — Side Left" },
    { "value" => "SD02", "label" => "SD02 — Side Right" },
    { "value" => "TQ01", "label" => "TQ01 — Three-Quarter Front" },
    { "value" => "TQ02", "label" => "TQ02 — Three-Quarter Back" },
    { "value" => "TP01", "label" => "TP01 — Top-Down / Flat Lay" },
    { "value" => "TP02", "label" => "TP02 — Top-Down (Alt)" },
    { "value" => "DT01", "label" => "DT01 — Detail / Macro" },
    { "value" => "DT02", "label" => "DT02 — Detail (Alt)" },
    { "value" => "DT03", "label" => "DT03 — Label / Callout" },
  ].freeze

  # @return [void]
  def self.seed!
    new.seed!
  end

  def seed!
    seed_default_root!
    seed_collection_root!
    seed_product_images_root!
  end

  private

  # ── Default (by MIME type) ────────────────────────────────────────────────

  def seed_default_root!
    default_root = ensure_schema!(
      name: "Default", slug: "default", level: "root",
      description: "Global fallback schema. Used when no other schema resolves.",
      tabs: [ basic_tab, iptc_tab, camera_tab ]
    )

    image = ensure_schema!(
      name: "Image", slug: "default--image", level: "type",
      parent_id: default_root.id, mime_segment: "image",
      description: "Applies to all image/* assets under the Default root.", tabs: []
    )

    %w[jpeg png tiff gif webp].each do |sub|
      ensure_schema!(
        name: sub.upcase, slug: "default--image--#{sub}", level: "subtype",
        parent_id: image.id, mime_segment: sub,
        description: "Schema for image/#{sub} assets.", tabs: []
      )
    end

    application = ensure_schema!(
      name: "Application", slug: "default--application", level: "type",
      parent_id: default_root.id, mime_segment: "application",
      description: "Applies to all application/* assets under the Default root.", tabs: []
    )

    { "pdf" => "PDF", "zip" => "ZIP Archive" }.each do |ms, label|
      ensure_schema!(
        name: label, slug: "default--application--#{ms}", level: "subtype",
        parent_id: application.id, mime_segment: ms, tabs: []
      )
    end

    ensure_schema!(
      name: "Video", slug: "default--video", level: "type",
      parent_id: default_root.id, mime_segment: "video",
      description: "Applies to all video/* assets under the Default root.", tabs: []
    )
  end

  # ── Collection ─────────────────────────────────────────────────────────────

  def seed_collection_root!
    ensure_schema!(
      name: "Collection", slug: "collection", level: "root",
      description: "Default schema applied to asset collections.",
      tabs: [
        { "id" => "tab-col", "name" => "Basic", "position" => 0,
          "fields" => [
            field("text",     "Collection Name", "dam:collectionName", 0, required: true),
            field("textarea", "Summary",         "dam:collectionDesc", 1),
            field("tags",     "Tags",            "dam:tags",           2),
            field("select",   "Visibility",      "dam:visibility",     3,
                  options: [ { "value" => "public",     "label" => "Public" },
                            { "value" => "internal",   "label" => "Internal" },
                            { "value" => "restricted", "label" => "Restricted" } ]),
          ] },
      ]
    )
  end

  # ── Product Images ───────────────────────────────────────────────────────

  def seed_product_images_root!
    ensure_schema!(
      name: "Product Images", slug: "product-images", level: "root",
      description: "Schema for product photography assets.",
      tabs: [
        basic_tab,
        { "id" => "tab-prod", "name" => "Product", "position" => 1,
          "fields" => [
            field("text",   "SKU",            "dam:sku",         0, required: true),
            field("text",   "Product Name",   "dam:productName", 1),
            field("text",   "Brand",          "dam:brand",       2),
            field("text",   "Color",          "dam:color",       3),
            field("text",   "Size / Variant", "dam:variant",     4),
            field("select", "Shot Type",      "dam:shotType",    5,
                  options: [ { "value" => "hero",      "label" => "Hero" },
                            { "value" => "lifestyle", "label" => "Lifestyle" },
                            { "value" => "detail",    "label" => "Detail" },
                            { "value" => "swatch",    "label" => "Swatch" } ]),
            field("select", "Asset Type / View Angle", "dam:asset_type", 6,
                  required: true, options: ASSET_TYPE_OPTIONS),
            field("text",   "Campaign",       "dam:campaign",    7),
            field("tags",   "Tags",           "dam:tags",        8),
          ] },
      ]
    )
  end

  # ── Shared tab builders (mirrors the original migration's fixtures) ───────

  def basic_tab
    { "id" => "tab-basic", "name" => "Basic", "position" => 0,
      "fields" => [
        field("text",     "Title",        "dc:title",       0, required: true),
        field("textarea", "Description",  "dc:description", 1),
        field("text",     "Creator",      "dc:creator",     2),
        field("date",     "Date Created", "dc:date",        3),
        field("text",     "Rights",       "dc:rights",      4),
      ] }
  end

  def iptc_tab
    { "id" => "tab-iptc", "name" => "IPTC", "position" => 1,
      "fields" => [
        field("text",     "Headline", "Iptc4xmpCore:Headline",    0),
        field("text",     "Byline",   "Iptc4xmpCore:Byline",      1),
        field("text",     "Credit",   "Iptc4xmpCore:CreditLine",  2),
        field("text",     "Source",   "Iptc4xmpCore:Source",      3),
        field("textarea", "Caption",  "Iptc4xmpCore:Description", 4),
        field("text",     "City",     "Iptc4xmpCore:City",        5),
        field("text",     "Country",  "Iptc4xmpCore:CountryName", 6),
        field("tags",     "Keywords", "Iptc4xmpCore:SubjectCode", 7),
      ] }
  end

  def camera_tab
    { "id" => "tab-camera", "name" => "Camera", "position" => 2,
      "fields" => [
        field("text", "Camera Make",   "exif:Make",              0, read_only: true),
        field("text", "Camera Model",  "exif:Model",             1, read_only: true),
        field("text", "Focal Length",  "exif:FocalLength",       2, read_only: true),
        field("text", "Aperture",      "exif:ApertureValue",     3, read_only: true),
        field("text", "ISO",           "exif:ISOSpeedRatings",   4, read_only: true),
        field("text", "Shutter Speed", "exif:ShutterSpeedValue", 5, read_only: true),
      ] }
  end

  def field(type, label, property, position, required: false, read_only: false, options: nil)
    f = {
      "id"              => SecureRandom.uuid,
      "field_type"      => type,
      "label"           => label,
      "map_to_property" => property,
      "position"        => position,
      "required"        => required,
      "read_only"       => read_only,
      "rules"           => {},
    }
    f["options"] = options if options
    f
  end

  # Creates the built-in schema if it is entirely missing, restores it if it
  # was soft-deleted (without altering its stored data), or leaves it
  # untouched if it already exists and is active — so re-running this seeder
  # is always safe and never overwrites an admin's customisations.
  #
  # @return [MetadataSchema]
  def ensure_schema!(name:, slug:, level:, description: nil, parent_id: nil,
                      mime_segment: nil, tabs: [])
    existing = MetadataSchema.unscoped.find_by(slug: slug)

    if existing
      existing.update!(deleted_at: nil, is_builtin: true) if existing.deleted_at.present? || !existing.is_builtin
      return existing
    end

    MetadataSchema.create!(
      name: name, slug: slug, level: level, description: description,
      parent_id: parent_id, mime_segment: mime_segment,
      is_builtin: true, tabs: tabs
    )
  end
end
