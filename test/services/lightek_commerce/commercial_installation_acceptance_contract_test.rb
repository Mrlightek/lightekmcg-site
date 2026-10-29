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

  test "mail bootstrap includes private IMAP service" do
    server = Rails.root.join("lib/scripts/lightek_mail_server.py").read
    installer = Rails.root.join("lib/scripts/setup_lightek_mail_node.sh").read
    assert_includes server, "dovecot-imapd"
    assert_includes server, "dovecot/conf.d/99-lightek.conf"
    assert_includes server, 'listen = 127.0.0.1'
    assert_includes installer, "systemctl is-active --quiet dovecot"
  end

  test "virtual mailboxes use private hashed credentials and persistent Maildir" do
    config = Rails.root.join("lib/scripts/lightek_mail_server.py").read
    mailbox = Rails.root.join("lib/scripts/lightek_mailbox.py").read
    assert_includes config, "driver = passwd-file"
    assert_includes config, "maildir:/var/vmail/%d/%n/Maildir"
    assert_includes mailbox, '["doveadm", "pw", "-s", "SHA512-CRYPT"'
    assert_includes mailbox, 'os.replace(tmp, USERS)'
    assert_includes mailbox, '"Maildir"'
  end

  test "Postfix accepts provisioned virtual mailboxes through Dovecot LMTP" do
    config = Rails.root.join("lib/scripts/lightek_mail_server.py").read
    provisioner = Rails.root.join("lib/scripts/lightek_mailbox.py").read
    assert_includes config, "virtual_mailbox_domains = hash:/etc/postfix/lightek_domains"
    assert_includes config, "virtual_mailbox_maps = hash:/etc/postfix/lightek_recipients"
    assert_includes config, "virtual_transport = lmtp:unix:private/dovecot-lmtp"
    assert_includes config, "smtpd_sasl_type = dovecot"
    assert_includes provisioner, "postfix/lightek_recipients"
    assert_includes provisioner, '["postmap", str(path)]'
  end

  test "inbound SMTP is not an authenticated submission relay" do
    config = Rails.root.join("lib/scripts/lightek_mail_server.py").read
    assert_includes config, "smtpd_sasl_auth_enable = no"
    assert_includes config, "postfix/lightek_logins"
    assert_includes config, "virtual_transport = lmtp:unix:private/dovecot-lmtp"
  end

  test "SMTP submission is staged with TLS and mailbox sender restrictions" do
    source = Rails.root.join("lib/scripts/lightek_mail_server.py").read
    mailbox = Rails.root.join("lib/scripts/lightek_mailbox.py").read
    assert_includes source, "postfix/lightek_submission.cf"
    assert_includes source, "smtpd_tls_security_level=encrypt"
    assert_includes source, "smtpd_tls_wrappermode=yes"
    assert_includes source, "reject_sender_login_mismatch"
    assert_includes mailbox, 'Path("/etc/postfix/lightek_logins")'
  end

  test "paid deployment provides initial mailbox address" do
    installer = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes installer, "LIGHTEK_MAIL_INITIAL_ADDRESS"
  end

  test "existing mail nodes retry mailbox provisioning without reinstalling services" do
    installer = Rails.root.join("lib/scripts/setup_lightek_mail_node.sh").read
    deploy = Rails.root.join("script/lightek/website_deploy.sh").read
    assert_includes installer, "--mailbox-only"
    assert_includes deploy, "--mailbox-only"
    assert_includes deploy, "lightek_mail_account_bootstrap.rb"
  end

  test "initial Rails mailbox registration is owner-bound and sending-disabled" do
    source = Rails.root.join("script/lightek_mail_account_bootstrap.rb").read
    assert_includes source, "User.find_by!"
    assert_includes source, "Mailbox domain belongs to another user"
    assert_includes source, "account.enabled = false if account.new_record?"
  end

  test "Gatekeeper requires full application acceptance before returning success" do
    source = Rails.root.join("app/services/gatekeeper/website_deployment.rb").read
    assert_includes source, 'receipt.dig("health", "full_application_dashboard_verified") == true'
  end
end
