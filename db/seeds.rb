puts "--- 🏗️  Seeding Capri DAM Ecosystem ---"

# ---------------------------------------------------------------------------
# 1. Built-in system groups
# ---------------------------------------------------------------------------

[
  { slug: 'everyone',            name: 'everyone',
    description: 'Every DAM user is implicitly a member of this group.' },
  { slug: 'administrators',      name: 'administrators',
    description: 'Members have full access. Only super-admins can modify this group.' },
  { slug: 'super-administrators', name: 'super-administrators',
    description: 'Reserved for the highest level of system operations.' },
  { slug: 'metadata_users',       name: 'metadata_users',
    description: 'Members can create, duplicate, edit, and delete custom metadata schemas ' \
                 'under Tools › Metadata Schemas. Non-members have read-only access.' },
].each do |attrs|
  # Case-insensitive lookup covers legacy capitalisation like "Everyone"
  group = UserGroup.find_by(slug: attrs[:slug]) ||
          UserGroup.where('lower(name) = ?', attrs[:name].downcase).first ||
          UserGroup.new

  if group.persisted?
    group.update_columns(
      name:        attrs[:name],
      slug:        attrs[:slug],
      is_system:   true,
      description: attrs[:description]
    )
  else
    group.assign_attributes(attrs.merge(is_system: true))
    group.save!
  end

  puts "✅ Built-in group: #{group.name}"
end

everyone_group     = UserGroup.find_by!(slug: 'everyone')
admins_group       = UserGroup.find_by!(slug: 'administrators')
super_admins_group = UserGroup.find_by!(slug: 'super-administrators')

# ---------------------------------------------------------------------------
# 2. Main Admin User
# ---------------------------------------------------------------------------

admin = User.find_or_create_by!(email: 'admin@admin.com') do |user|
  user.username              = 'admin'
  user.name                  = 'System Admin'
  user.password              = 'AdminUser'
  user.password_confirmation = 'AdminUser'
  user.admin                 = true
end
puts "✅ Admin: #{admin.email}"

[ admins_group, super_admins_group, everyone_group ].each do |group|
  unless admin.user_groups.include?(group)
    admin.user_groups << group
    puts "  ↳ Added admin to #{group.name}"
  end
end

# ---------------------------------------------------------------------------
# 2b. E2E / Playwright fixture users
# ---------------------------------------------------------------------------
# A handful of e2e specs (impersonation, header impersonate/groups switcher,
# style/model hub folder access) need distinct roles beyond the single
# super-admin account above: a second super-admin (to test "super-admin
# cannot impersonate another super-admin"), a plain non-admin target user,
# and a non-admin "member" user. These are dev/test-only fixtures — never
# used in production flows — so they're safe to seed idempotently.

superadmin = User.find_or_create_by!(email: 'superadmin@example.com') do |user|
  user.username              = 'e2e_superadmin'
  user.name                  = 'E2E Super Admin'
  user.password              = 'Password123!'
  user.password_confirmation = 'Password123!'
  user.admin                 = true
end
[ admins_group, super_admins_group, everyone_group ].each do |group|
  superadmin.user_groups << group unless superadmin.user_groups.include?(group)
end
puts "✅ E2E fixture: #{superadmin.email}"

target_user = User.find_or_create_by!(email: 'user@example.com') do |user|
  user.username              = 'e2e_target_user'
  user.name                  = 'E2E Target User'
  user.password              = 'Password123!'
  user.password_confirmation = 'Password123!'
  user.admin                 = false
end
puts "✅ E2E fixture: #{target_user.email}"

member_user = User.find_or_create_by!(email: 'member@example.com') do |user|
  user.username              = 'e2e_member_user'
  user.name                  = 'E2E Member User'
  user.password              = 'password'
  user.password_confirmation = 'password'
  user.admin                 = false
end
puts "✅ E2E fixture: #{member_user.email}"

# ---------------------------------------------------------------------------
# 3. System API User
# ---------------------------------------------------------------------------

system_user = User.find_or_create_by!(email: 'system@headless-dam.local') do |user|
  user.username = 'system_api'
  user.name     = 'System Account'
  user.password = SecureRandom.hex(16)
  user.admin    = false
end
puts "✅ System User: #{system_user.email}"

# ---------------------------------------------------------------------------
# 4. Default Storage Backend
# ---------------------------------------------------------------------------

backend = StorageBackend.find_or_create_by!(name: 'Local Disk') do |sb|
  sb.provider_type = 'local'
  sb.active        = true
  sb.configuration = { root_path: 'storage/dam' }
end
puts "✅ Storage Backend: #{backend.name}"

# ---------------------------------------------------------------------------
# 5. Built-in Metadata Schemas (Default / Collection / Product Images)
# ---------------------------------------------------------------------------
# Idempotent: safe to re-run in any environment. Restores schemas that are
# missing or were soft-deleted, without touching ones that already exist and
# are active. See MetadataSchemaSeeder for why this must live here (not only
# in the historical migration) — `db:schema:load`/`db:prepare` skips migration
# Ruby code entirely, so a fresh database would otherwise have none of these.
MetadataSchemaSeeder.seed!
MetadataSchemaSeeder.upgrade_default_tabs!
puts "✅ Built-in metadata schemas: Default, Collection, Product Images"

puts "---  Seed Complete! ---"


# ---------------------------------------------------------------------------
# Report Definitions (built-in types)
# ---------------------------------------------------------------------------
require_relative 'seeds/report_definitions'
