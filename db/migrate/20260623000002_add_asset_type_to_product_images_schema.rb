class AddAssetTypeToProductImagesSchema < ActiveRecord::Migration[8.1]
  ASSET_TYPE_OPTIONS = [
    # Front angles
    { 'value' => 'FR01', 'label' => 'FR01 — Front (Primary)' },
    { 'value' => 'FR02', 'label' => 'FR02 — Front (Alt)' },
    { 'value' => 'FR03', 'label' => 'FR03 — Front Detail' },
    # Back angles
    { 'value' => 'BK01', 'label' => 'BK01 — Back (Primary)' },
    { 'value' => 'BK02', 'label' => 'BK02 — Back (Alt)' },
    # Side / Profile
    { 'value' => 'SD01', 'label' => 'SD01 — Side Left' },
    { 'value' => 'SD02', 'label' => 'SD02 — Side Right' },
    # Three-Quarter / 45°
    { 'value' => 'TQ01', 'label' => 'TQ01 — Three-Quarter Front' },
    { 'value' => 'TQ02', 'label' => 'TQ02 — Three-Quarter Back' },
    # Top-Down / Flat Lay
    { 'value' => 'TP01', 'label' => 'TP01 — Top-Down / Flat Lay' },
    { 'value' => 'TP02', 'label' => 'TP02 — Top-Down (Alt)' },
    # Detail / Macro
    { 'value' => 'DT01', 'label' => 'DT01 — Detail / Macro' },
    { 'value' => 'DT02', 'label' => 'DT02 — Detail (Alt)' },
    { 'value' => 'DT03', 'label' => 'DT03 — Label / Callout' }
  ].freeze

  def up
    schema = MetadataSchema.find_by(slug: 'product-images')
    return unless schema

    tabs          = schema.tabs.deep_dup
    prod_tab_idx  = tabs.index { |t| t['id'] == 'tab-prod' }
    return unless prod_tab_idx

    fields = tabs[prod_tab_idx]['fields']

    # Insert dam:asset_type right after dam:shotType (position 5)
    shot_idx = fields.index { |f| f['map_to_property'] == 'dam:shotType' }
    insert_at = shot_idx ? shot_idx + 1 : fields.length

    asset_type_field = {
      'id'              => SecureRandom.uuid,
      'field_type'      => 'select',
      'label'           => 'Asset Type / View Angle',
      'map_to_property' => 'dam:asset_type',
      'position'        => insert_at,
      'required'        => true,
      'read_only'       => false,
      'rules'           => {},
      'options'         => ASSET_TYPE_OPTIONS
    }

    fields.insert(insert_at, asset_type_field)

    # Re-index positions
    fields.each_with_index { |f, i| f['position'] = i }

    tabs[prod_tab_idx]['fields'] = fields
    schema.update_columns(tabs: tabs, updated_at: Time.current)
  end

  def down
    schema = MetadataSchema.find_by(slug: 'product-images')
    return unless schema

    tabs         = schema.tabs.deep_dup
    prod_tab_idx = tabs.index { |t| t['id'] == 'tab-prod' }
    return unless prod_tab_idx

    tabs[prod_tab_idx]['fields'].reject! { |f| f['map_to_property'] == 'dam:asset_type' }
    tabs[prod_tab_idx]['fields'].each_with_index { |f, i| f['position'] = i }
    schema.update_columns(tabs: tabs, updated_at: Time.current)
  end
end

