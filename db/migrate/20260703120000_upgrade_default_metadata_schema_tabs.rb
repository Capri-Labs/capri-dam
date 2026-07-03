# frozen_string_literal: true

# Corrects the built-in "Default" metadata schema's tabs to use real
# XMP/IPTC-standard namespace prefixes (e.g. `tiff:Make` instead of the
# incorrect `exif:Make`, `photoshop:Headline` instead of the non-standard
# `Iptc4xmpCore:Headline`) and adds three new conditionally-visible tabs (XMP,
# Photoshop, ICC Profile) — see {EmbeddedMetadataMapper} and
# {MetadataSchemaSeeder} for the full rationale.
#
# Environments provisioned before this migration already have a "Default"
# schema row with the old (incorrect) tab definitions; {MetadataSchemaSeeder}
# deliberately never rewrites an already-active schema's tabs (to protect
# admin customisations), so this migration calls the dedicated
# +MetadataSchemaSeeder.upgrade_default_tabs!+ method instead, which merges
# only the built-in tabs by id and leaves any custom tabs an admin added
# untouched.
class UpgradeDefaultMetadataSchemaTabs < ActiveRecord::Migration[8.1]
  def up
    MetadataSchemaSeeder.upgrade_default_tabs!
  end

  def down
    # Intentionally a no-op: reverting would mean re-introducing the
    # incorrect/non-standard namespace prefixes, which is never desirable.
    # If a rollback is truly needed, restore from a database backup instead.
  end
end
