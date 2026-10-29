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
    assert_includes script, "c.get('_headless') or os.environ.get('LIGHTEK_INSTALL_PRIVATE_MAIL_NODE')=='true'"
    assert_includes script, "lib/scripts/setup_lightek_mail_node.sh"
    assert_includes script, "LIGHTEK_MAIL_PRIVATE_NODE_READY"
  end

  test "cloud mail port restrictions do not prevent paid installation acceptance" do
    script = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes script, "LIGHTEK_INSTALL_PRIVATE_MAIL_NODE"
    refute_includes script, "Customer mail is not fully operational; installation is not ready"
  end

  test "paid installation submits cloud mail port request without delaying activation" do
    source = Rails.root.join("app/services/lightek_commerce/paid_instance_provisioning.rb").read
    assert_includes source, "mail_port_ticket_attempted"
    assert_includes source, "create_support_ticket("
    assert_includes source, "mail_port_ticket_status"
  end

  test "external authoritative DNS is supported without a GoDaddy account" do
    script = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes script, "authoritative DNS provider"
    assert_includes script, "GoDaddy is optional."
  end

  test "Gatekeeper requires full application acceptance before returning success" do
    source = Rails.root.join("app/services/gatekeeper/website_deployment.rb").read
    assert_includes source, 'receipt.dig("health", "full_application_dashboard_verified") == true'
  end
end
