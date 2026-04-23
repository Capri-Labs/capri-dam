# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

puts "--- Seeding Data ---"

# Create a default Admin user
admin = User.find_or_create_by!(email: 'admin@admin.com') do |user|
  user.username = 'admin'
  user.name     = 'System Admin'
  user.password = 'AdminUser'
  user.password_confirmation = 'AdminUser'
  user.admin    = true
end
