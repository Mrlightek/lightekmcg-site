require "test_helper"

class WebsitePlanV8Test < ActiveSupport::TestCase
  test "website without domain gets Lightek subdomain" do
    plan = Gatekeeper::Compute::ProvisioningExecutionService.website_plan_v8(account_key: "example-client")
    assert_equal "example-client.lightekmcg.com", plan.fetch("hostname")
    assert_equal false, plan.fetch("domain_purchase_required")
    assert_equal "planned", plan.fetch("status")
  end

  test "custom domain and apps remain separate options" do
    plan = Gatekeeper::Compute::ProvisioningExecutionService.website_plan_v8(account_key: "client-2", custom_domain: "client.example", include_apps: true)
    assert_equal "client.example", plan.fetch("hostname")
    assert_equal "client-2.lightekmcg.com", plan.fetch("default_subdomain")
    assert_includes plan.fetch("thin_clients"), "ios"
    assert_includes plan.fetch("thin_clients"), "roku"
  end

  test "invalid account key does not produce hostname" do
    assert_raises(ArgumentError) { Gatekeeper::Compute::ProvisioningExecutionService.website_plan_v8(account_key: "not a hostname") }
  end
end
