# frozen_string_literal: true

# Adds root-to-root schema inheritance, independent of the existing
# `parent_id` column (which is reserved for the type/subtype MIME-resolution
# hierarchy — see {MetadataSchema.resolve_for_mime}).
#
# `inherits_from_id` lets an admin/`metadata_users` member pick another
# *root*-level schema to inherit tabs from via a dropdown in the schema
# editor. This is what powers "Duplicate as new custom schema": the new copy
# is linked back to the original via `inherits_from_id` (tabs are NOT deep
# copied), so it shows the original's tabs read-only (inherited) plus
# whatever new tabs the admin adds — and stays in sync if the original is
# later edited. See {MetadataSchema#resolved_tabs}.
class AddInheritsFromToMetadataSchemas < ActiveRecord::Migration[8.1]
  def change
    add_column :metadata_schemas, :inherits_from_id, :bigint
    add_index  :metadata_schemas, :inherits_from_id
    add_foreign_key :metadata_schemas, :metadata_schemas, column: :inherits_from_id
  end
end
