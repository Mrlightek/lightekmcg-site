namespace :gatekeeper do
  desc "Register Infrastructure and Susu in DymondDash navigation"
  task dashboard_nav: :environment do
    operations = DymondDash::NavSection.find_or_initialize_by(slug: "operations")
    operations.label = "Operations"
    operations.position = 80 if operations.position.to_i.zero?
    operations.save!

    services = DymondDash::NavSection.find_or_initialize_by(slug: "services")
    services.label = "Services"
    services.position = 60 if services.position.to_i.zero?
    services.save!

    infrastructure = DymondDash::NavItem.find_or_initialize_by(section: operations, label: "Infrastructure")
    infrastructure.assign_attributes(icon: "server", path_helper: "dashboard_infrastructure_path", position: 10, visible: true, feature_slug: nil)
    infrastructure.save!

    susu = DymondDash::NavItem.find_or_initialize_by(section: services, label: "Susu")
    susu.assign_attributes(icon: "users-group", path_helper: "dashboard_susu_path", position: 90, visible: true, feature_slug: nil)
    susu.save!

    puts "DymondDash navigation registered:"
    puts "  Operations -> Infrastructure"
    puts "  Services   -> Susu"
  end
end
