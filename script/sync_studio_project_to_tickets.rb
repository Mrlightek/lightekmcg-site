# frozen_string_literal: true

result =
  ProjectTracking::StudioTicketSync.call

puts
puts "===== LIGHTEK TICKET SYNC COMPLETE ====="
puts "Project: #{result.fetch(:project_key)}"
puts "Tracked: #{result.fetch(:total)}"
puts "Created: #{result.fetch(:created)}"
puts "Updated: #{result.fetch(:updated)}"
puts "Unchanged: #{result.fetch(:unchanged)}"
puts "Status changes: #{result.fetch(:status_changed)}"
