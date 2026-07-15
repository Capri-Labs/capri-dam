# Builds a one-off, throwaway {MetadataSchema} named "MAM Global" for customer
# demos, modelled on a real AEM Assets metadata schema XML export provided by
# the customer (Granite UI dialog: `mamAssetType` cascades to
# `mamAssetSubType`; `mamCategoryGroup` cascades to `mamCommodityGroup`).
#
# == Scope note
#
# The source XML's Category/Commodity Group cascade references several
# hundred commodity + sub-commodity options across ~18 categories; only a
# representative slice ("Alcoholic Beverages" → its 4 commodities) is
# reproduced here, since the full customer master list was not available.
# This is intentional: the goal of this schema is to demonstrate the
# platform's cascading-dropdown feature end-to-end for the demo, not to ship
# the customer's complete taxonomy. Admins can extend the Category/Commodity
# options and cascade map afterwards via the Metadata Schema editor's
# "Cascades From" UI (see {SchemaEditorDialog}), or this schema can simply be
# deleted once the demo is over.
#
# Re-running {.seed!} is safe: it updates the existing "mam-global-demo"
# schema in place (by slug) rather than creating duplicates.
class MamGlobalDemoSchemaSeeder
  SLUG = "mam-global-demo".freeze

  ASSET_TYPE_OPTIONS = [
    { "value" => "Product",   "label" => "Product" },
    { "value" => "Lifestyle", "label" => "Lifestyle" },
    { "value" => "Brand",     "label" => "Brand" },
  ].freeze

  ASSET_SUB_TYPE_OPTIONS = [
    { "value" => "In Pack",                "label" => "In Pack" },
    { "value" => "In Use",                 "label" => "In Use" },
    { "value" => "Out Of Pack",            "label" => "Out Of Pack" },
    { "value" => "Product Group",          "label" => "Product Group" },
    { "value" => "Render",                 "label" => "Render" },
    { "value" => "Product Other",          "label" => "Product Other" },
    { "value" => "Motion",                 "label" => "Motion" },
    { "value" => "Recipe",                 "label" => "Recipe" },
    { "value" => "Buzzworthy",              "label" => "Buzzworthy" },
    { "value" => "Stock Imagery Lifestyle", "label" => "Stock Imagery Lifestyle" },
    { "value" => "Environmental",          "label" => "Environmental" },
    { "value" => "Meat and Seafood",        "label" => "Meat and Seafood" },
    { "value" => "Produce",                "label" => "Produce" },
    { "value" => "Lifestyle Other",        "label" => "Lifestyle Other" },
    { "value" => "Badges",                 "label" => "Badges" },
    { "value" => "Background",             "label" => "Background" },
    { "value" => "Store Imagery",          "label" => "Store Imagery" },
    { "value" => "Stock Imagery Brand",    "label" => "Stock Imagery Brand" },
    { "value" => "Brand Other",            "label" => "Brand Other" },
  ].freeze

  # parent Asset Type value → allowed Asset Sub-Type values (from the
  # source XML's <cascadeitems> block).
  ASSET_SUB_TYPE_CASCADE_MAP = {
    "Product"   => %w[In\ Pack In\ Use Out\ Of\ Pack Product\ Group Render Product\ Other],
    "Lifestyle" => [ "Motion", "Recipe", "Buzzworthy", "Stock Imagery Lifestyle", "Environmental",
                     "Meat and Seafood", "Produce", "Lifestyle Other" ],
    "Brand"     => [ "Badges", "Background", "Store Imagery", "Stock Imagery Brand", "Brand Other" ],
  }.freeze

  CATEGORY_GROUP_OPTIONS = [
    { "value" => "0001", "label" => "(0001) Alcoholic Beverages" },
    { "value" => "0002", "label" => "(0002) Bakery" },
    { "value" => "0003", "label" => "(0003) Breakfast" },
    { "value" => "0004", "label" => "(0004) Dairy" },
    { "value" => "0005", "label" => "(0005) Chilled Convenience" },
    { "value" => "0006", "label" => "(0006) Fresh Meat & Fish" },
    { "value" => "0007", "label" => "(0007) Freezer" },
    { "value" => "0008", "label" => "(0008) Fruits & Vegetables" },
    { "value" => "0009", "label" => "(0009) Pantry" },
    { "value" => "0010", "label" => "(0010) Non-Alcoholic Beverages" },
    { "value" => "0011", "label" => "(0011) Snacking" },
    { "value" => "0012", "label" => "(0012) Electronics" },
    { "value" => "0013", "label" => "(0013) Fashion" },
    { "value" => "0014", "label" => "(0014) Health, Beauty & Baby" },
    { "value" => "0015", "label" => "(0015) Home Improvement" },
    { "value" => "0016", "label" => "(0016) Household" },
    { "value" => "0017", "label" => "(0017) Outdoor/Leisure" },
    { "value" => "0018", "label" => "(0018) Services" },
  ].freeze

  # Only "Alcoholic Beverages" (0001) has its full commodity list from the
  # source XML before the export was truncated — see the class-level scope
  # note. Every other category is left without commodities so the cascade
  # correctly renders as "no options yet" rather than fabricating data.
  COMMODITY_GROUP_OPTIONS = [
    { "value" => "000101", "label" => "(01) Spirits" },
    { "value" => "000102", "label" => "(02) Sparkling wine" },
    { "value" => "000103", "label" => "(03) Wine" },
    { "value" => "000104", "label" => "(04) Beer" },
  ].freeze

  COMMODITY_GROUP_CASCADE_MAP = {
    "0001" => %w[000101 000102 000103 000104],
  }.freeze

  # @return [MetadataSchema]
  def self.seed!
    new.seed!
  end

  # @return [void]
  def self.remove!
    MetadataSchema.unscoped.find_by(slug: SLUG)&.soft_delete!
  end

  def seed!
    existing = MetadataSchema.unscoped.find_by(slug: SLUG)
    attrs = {
      name:        "MAM Global",
      slug:        SLUG,
      level:       "root",
      description: "Demo schema derived from the customer's AEM Assets \"MAM Global\" metadata " \
                   "schema export — includes cascading dropdowns (Asset Type → Asset Sub-Type, " \
                   "Category Group → Commodity Group). Delete after the demo.",
      is_builtin:  false,
      deleted_at:  nil,
      tabs:        [ mam_global_tab ],
    }

    if existing
      existing.update!(attrs)
      existing
    else
      MetadataSchema.create!(attrs)
    end
  end

  private

  def mam_global_tab
    {
      "id"       => "tab-mam-global",
      "name"     => "MAM Global",
      "position" => 0,
      "fields"   => [
        field("date", "Date of upload", "mamDateOfUpload", 0, read_only: true),
        field("select", "Asset Type", "mamAssetType", 1, required: true, options: ASSET_TYPE_OPTIONS),
        field("select", "Asset Sub-Type", "mamAssetSubType", 2, required: true,
              options: ASSET_SUB_TYPE_OPTIONS,
              cascade: { "parent_field_id" => "field-mam-asset-type", "map" => ASSET_SUB_TYPE_CASCADE_MAP }),
        field("select", "Category Group", "mamCategoryGroup", 3, options: CATEGORY_GROUP_OPTIONS),
        field("select", "Commodity Group", "mamCommodityGroup", 4,
              options: COMMODITY_GROUP_OPTIONS,
              cascade: { "parent_field_id" => "field-mam-category-group", "map" => COMMODITY_GROUP_CASCADE_MAP }),
      ].tap { |fields| assign_stable_ids!(fields) },
    }
  end

  # Asset Type / Category Group need predictable ids so the cascade
  # `parent_field_id` references above resolve correctly.
  STABLE_FIELD_IDS = {
    "mamAssetType"     => "field-mam-asset-type",
    "mamCategoryGroup" => "field-mam-category-group",
  }.freeze

  def assign_stable_ids!(fields)
    fields.each do |f|
      stable_id = STABLE_FIELD_IDS[f["map_to_property"]]
      f["id"] = stable_id if stable_id
    end
  end

  def field(type, label, property, position, required: false, read_only: false, options: nil, cascade: nil)
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
    f["rules"] = { "cascade" => cascade } if cascade
    f
  end
end
