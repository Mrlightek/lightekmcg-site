namespace :gatekeeper do
  desc "Show Gatekeeper infrastructure, trouble-ticket, and Marlon dependency status"
  task infrastructure_status: :environment do
    metrics = Gatekeeper::Metrics.summary

    puts "Nodes:                 #{GatekeeperNode.count}"
    puts "Projects:              #{GatekeeperProject.count}"
    puts "Operations:            #{metrics[:operations]}"
    puts "Succeeded:             #{metrics[:succeeded]}"
    puts "Failed:                #{metrics[:failed]}"
    puts "Support tickets:       #{metrics[:support_tickets]}"
    puts "Need intervention:     #{metrics[:open_support_tickets]}"
    puts "Human interventions:   #{metrics[:human_interventions]}"
    puts format("Marlon dependency:    %.2f%%", metrics[:marlon_dependency_rate] * 100)
  end
end
