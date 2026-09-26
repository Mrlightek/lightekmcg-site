namespace :lightek do
  desc "Compact production status for Gatekeeper/Nevaeh"
  task production_status: :environment do
    puts "=== LIGHTEK PRODUCTION STATUS ==="
    puts "Rails:               #{Rails.version}"
    puts "Environment:         #{Rails.env}"
    puts "Gatekeeper nodes:    #{GatekeeperNode.count}"
    puts "Gatekeeper projects: #{GatekeeperProject.count}"
    puts "Operations:          #{GatekeeperOperation.count}"

    gatekeeper_tickets =
      if defined?(Marlon::Ticket)
        Marlon::Ticket.where(related_type: "GatekeeperOperation")
      else
        []
      end

    puts "GK tickets:          #{gatekeeper_tickets.respond_to?(:count) ? gatekeeper_tickets.count : 0}"

    if defined?(SusuGroup)
      puts "Susu groups:         #{SusuGroup.count}"
      puts "Susu memberships:    #{SusuMembership.count}"
      puts "Susu contributions:  #{SusuContribution.count}"
    end
  end
end
