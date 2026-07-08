# frozen_string_literal: true

# Creates the built-in "metadata_users" system group (out-of-the-box,
# seeded automatically like `everyone`/`administrators`/`super-administrators`
# — see {UserGroup::SYSTEM_SLUGS}).
#
# Membership in this group is the gate for managing custom Metadata Schemas
# (create / duplicate / edit / delete) — see
# {Api::V1::MetadataSchemasController#ensure_schema_manager!} and
# {User#metadata_schema_manager?}. Admins and super-admins can freely add or
# remove members via the existing Admin > User Groups screen (the group
# itself is protected the same way the other system groups are — its
# `slug`/`is_system` flag cannot be changed and it cannot be deleted — but
# membership is fully editable, exactly like any other group).
#
# Non-members (and non-admins) retain read-only access to
# `/tools/metadata_schemas`.
class CreateMetadataUsersSystemGroup < ActiveRecord::Migration[8.1]
  def up
    UserGroup.find_or_create_by!(slug: "metadata_users") do |group|
      group.name        = "metadata_users"
      group.is_system    = true
      group.description  = "Members can create, duplicate, edit, and delete custom Metadata Schemas. " \
                            "Everyone else has read-only access to Tools > Metadata Schemas."
    end
  end

  def down
    # Intentionally a no-op — system groups are never deleted by migrations
    # (matches the existing `everyone`/`administrators`/`super-administrators`
    # precedent; UserGroup#prevent_system_group_deletion would block a
    # `destroy` here anyway).
  end
end
