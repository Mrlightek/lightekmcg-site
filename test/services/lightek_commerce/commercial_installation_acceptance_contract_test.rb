require "test_helper"

class CommercialInstallationAcceptanceContractTest < ActiveSupport::TestCase
  test "installer verifies complete authenticated Lightek dashboard surface" do
    script = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes script, "'/dashboard/business'"
    assert_includes script, "'/dashboard/commerce/orders?site_id='"
    assert_includes script, "'/dashboard/settings'"
    assert_includes script, "h['full_application_dashboard_verified']=True"
    assert_includes script, "dest.rstrip('/')!=path"
  end

  test "Gatekeeper requires full application acceptance before returning success" do
    source = Rails.root.join("app/services/gatekeeper/website_deployment.rb").read
    assert_includes source, 'receipt.dig("health", "full_application_dashboard_verified") == true'
  end
end
