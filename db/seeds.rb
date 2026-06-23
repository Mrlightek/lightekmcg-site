# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# db/seeds.rb
if Rails.env.development?
  u = User.find_or_initialize_by(email_address: "marlon@lightekmcg.com")
  u.first_name = "Marlon"; u.last_name = "Henry"; u.role = "super_admin"
  u.password = ENV.fetch("SEED_ADMIN_PASSWORD", "LotusBloom520!")
  u.password_confirmation = u.password
  u.save!
  puts "Seeded super_admin #{u.email_address}"
end
