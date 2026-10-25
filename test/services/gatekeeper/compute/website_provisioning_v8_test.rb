require "test_helper"

class WebsiteProvisioningV8Test < ActiveSupport::TestCase
  test "website execution entry point is wired into existing Gatekeeper executor" do
    assert_respond_to Gatekeeper::Compute::ProvisioningExecutionService, :provision_website_v8!
  end

  test "website provisioning requires an active persisted subscription" do
    before = DymondSite::Site.count
    assert_raises(Gatekeeper::Compute::WebsiteProvisioningV8::NotEntitled) do
      Gatekeeper::Compute::ProvisioningExecutionService.provision_website_v8!(
        subscription: nil, account_key: "v85-test", site_name: "Test Website"
      )
    end
    assert_equal before, DymondSite::Site.count
  end

  test "invalid account hostname is refused before creating a site" do
    assert_raises(ArgumentError) do
      Gatekeeper::Compute::ProvisioningExecutionService.website_plan_v8(account_key: "bad host")
    end
  end
end
