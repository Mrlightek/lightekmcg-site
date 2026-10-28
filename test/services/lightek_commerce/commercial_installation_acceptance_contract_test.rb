require "test_helper"

class CommercialInstallationAcceptanceContractTest < ActiveSupport::TestCase
  test "installer verifies complete authenticated Lightek dashboard surface" do
    script = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes script, "'/dashboard/business'"
    assert_includes script, "'/dashboard/commerce/orders?site_id='"
    assert_includes script, "'/dashboard/settings'"
    assert_includes script, "h['full_application_dashboard_verified']=True"
    assert_includes script, "dest.rstrip('/')!=expected"
  end

  test "private mail server uses the existing installer only with explicit opt in" do
    script = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes script, "LIGHTEK_INSTALL_PRIVATE_MAIL_NODE"
    assert_includes script, "lib/scripts/setup_lightek_mail_node.sh"
    assert_includes script, "LIGHTEK_MAIL_PRIVATE_NODE_READY"
  end

  test "paid installs require evidence of functioning inbound and outbound mail" do
    script = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes script, "inbound_received"
    assert_includes script, "outbound_delivered"
    assert_includes script, "mail_domain_verified"
    assert_includes script, "Customer mail is not fully operational"
  end

  test "Gatekeeper requires full application acceptance before returning success" do
    source = Rails.root.join("app/services/gatekeeper/website_deployment.rb").read
    assert_includes source, 'receipt.dig("health", "full_application_dashboard_verified") == true'
  end
end
