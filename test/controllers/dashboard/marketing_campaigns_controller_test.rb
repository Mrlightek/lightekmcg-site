require "test_helper"

class DashboardMarketingCampaignsTest < ActionDispatch::IntegrationTest
  test "marketing campaign routes are registered" do
    match = Rails.application.routes.recognize_path("/dashboard/marketing/campaigns", method: :get)
    assert_equal "dashboard/marketing_campaigns", match[:controller]
    assert_equal "index", match[:action]
  end
end
