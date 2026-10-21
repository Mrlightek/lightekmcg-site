# frozen_string_literal: true
require "test_helper"

class NevaehDashboardNavV7aTest < ActiveSupport::TestCase
  test "native registration uses only existing read-only console pages and tickets" do
    source = File.read(Rails.root.join("config/initializers/nevaeh_nav.rb"))
    assert_includes source, "DymondDash::FeatureRegistry.register"
    assert_includes source, "feature.slug = :nevaeh"
    assert_includes source, "feature.nav_section = :operations"
    assert_includes source, "main_app.employee_nevaeh_capabilities_path"
    assert_includes source, "main_app.employee_nevaeh_services_path"
    assert_includes source, "main_app.employee_tickets_path"
    refute_match(/generate|dispatch!|perform_later|production_execution\s*=\s*true/, source)
  end

  test "navigation targets correspond to registered GET routes" do
    routes = Rails.application.routes
    assert_equal "employee/nevaeh_capabilities", routes.recognize_path("/employee/nevaeh/capabilities", method: :get)[:controller]
    assert_equal "employee/nevaeh_capabilities", routes.recognize_path("/employee/nevaeh/services", method: :get)[:controller]
    assert_equal "employee/tickets", routes.recognize_path("/employee/tickets", method: :get)[:controller]
  end
end
