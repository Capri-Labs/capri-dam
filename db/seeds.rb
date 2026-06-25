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

puts "---  Seed Complete! ---"
