# frozen_string_literal: true

# Read-only candidate verification using the installed Rails/private-engine stack.
# Exercise actual production queries and both response formats without issuing
# credentials, changing tickets, dispatching work, or replacing the live checkout.
require "json"
require "rack/mock"
raise "Installed production runtime required" unless Rails.env.production?
candidate_root = File.expand_path("..", __dir__)
raise "Candidate must be separate from installed application" if File.realpath(candidate_root) == File.realpath(Rails.root)
NevaehIntelligences::YamlCapabilityRegistryV7a
load File.join(candidate_root, "app/services/nevaeh_intelligences/yaml_capability_registry_v7a.rb")
Employee::NevaehOverviewController
load File.join(candidate_root, "app/controllers/employee/nevaeh_overview_controller.rb")
controller_class = Employee::NevaehOverviewController
controller_class.prepend_view_path(File.join(candidate_root, "app/views"))

build_controller = lambda do |format|
  controller = controller_class.new
  controller.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/employee/nevaeh", "HTTP_ACCEPT" => "#{format == 'json' ? 'application/json' : 'text/html'}"))
  controller.send(:set_response!, ActionDispatch::Response.new)
  controller
end
html_controller = build_controller.call("html")
html_controller.index
assigns = %w[capabilities services registered_services present_services executable_services ticket_counts backlog_counts backlog_tickets].to_h do |key|
  [key, html_controller.instance_variable_get("@#{key}")]
end
html = controller_class.renderer.render(template: "employee/nevaeh_overview/index", layout: false, assigns: assigns)
raise "Overview HTML missing operating console" unless html.include?("Nevaeh operating system overview") && html.include?("Ticket processing") && html.include?("/employee/tickets")
raise "Overview status counts differ from ticket records" unless assigns.fetch("ticket_counts") == Marlon::Ticket.group(:status).count
json_controller = build_controller.call("json")
json_controller.index
raise "Overview JSON response failed" unless json_controller.response.status == 200 && json_controller.response.media_type == "application/json"
data = JSON.parse(json_controller.response.body)
raise "Overview JSON contract failed" unless data["read_only"] == true && data["summary"].is_a?(Hash) && data["services"].is_a?(Array) && data["tickets"].is_a?(Array)
puts "NEVAEH_OVERVIEW_ACCEPTANCE=#{JSON.generate(html_rendered: true, json_response_verified: true,
  production_ticket_queries_verified: true, yaml_capabilities: assigns.fetch('capabilities').size,
  service_entries: assigns.fetch('services').size, tickets_mutated: false)}"
