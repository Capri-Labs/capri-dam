# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

puts "--- 🏗️  Seeding Headless DAM Ecosystem ---"

# 1. Create the Main Admin (For UI Access)
admin = User.find_or_create_by!(email: 'admin@admin.com') do |user|
  user.username = 'admin'
  user.name     = 'System Admin'
  user.password = 'AdminUser'
  user.password_confirmation = 'AdminUser'
  user.admin = true
end
puts "✅ Created Admin: #{admin.email}"

# 2. Create the System User (For API/Service Accounts)
system_user = User.find_or_create_by!(email: 'system@headless-dam.local') do |user|
  user.username = 'system_api'        # Added this to pass validations
  user.name     = 'System Account'    # Changed from first/last_name to match your schema
  user.password = SecureRandom.hex(16)
  user.admin    = false
end
puts "✅ Created System User: #{system_user.email}"

# 3. Create a Default Local Storage Backend
backend = StorageBackend.find_or_create_by!(name: 'Local Disk') do |sb|
  sb.provider_type = 'local'
  sb.active = true
  sb.configuration = { root_path: 'storage/dam' }
end
puts "✅ Created Storage Backend: #{backend.name}"

# 4. Create an Initial Folder
# folder = Folder.find_or_create_by!(name: 'General Assets')
# puts "✅ Created Default Folder: #{folder.name}"

puts "--- 🚀 Seed Complete! ---"