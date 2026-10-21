# frozen_string_literal: true
require "test_helper"
class NevaehCapabilityConsoleRoutesV7aTest < ActionDispatch::IntegrationTest
  test "console routes support GET only" do
    assert_equal({ controller: "employee/nevaeh_capabilities", action: "index" }, Rails.application.routes.recognize_path("/employee/nevaeh/capabilities", method: :get))
    assert_equal({ controller: "employee/nevaeh_capabilities", action: "services" }, Rails.application.routes.recognize_path("/employee/nevaeh/services", method: :get))
    r = Rails.application.routes.recognize_path("/employee/nevaeh/capabilities/studio.asset.ingest", method: :get)
    assert_equal "show", r.fetch(:action)
    assert_equal "studio.asset.ingest", r.fetch(:key)
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/employee/nevaeh/capabilities", method: :post) }
  end

  test "anonymous request cannot read console JSON" do
    get "/employee/nevaeh/capabilities.json"
    refute response.successful?, "Anonymous access must be denied"
  end
end
