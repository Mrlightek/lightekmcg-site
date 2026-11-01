require "test_helper"

class PwaAdministrationTest < ActionDispatch::IntegrationTest
  def actor(role = "client")
    User.create!(first_name: "PWA", last_name: "Owner", role: role,
      email_address: "pwa-#{SecureRandom.hex(6)}@example.test", password: "Pwa-test-password-2026!")
  end
  def login(user)
    post "/session", params: {email_address: user.email_address, password: "Pwa-test-password-2026!"}
    assert_response :redirect
  end
  test "client owner can administer their PWA without a platform admin role" do
    owner = actor
    site = DymondSite::Site.create!(name: "Client app", host: "pwa-#{SecureRandom.hex(6)}.example.test", tenant: owner)
    login(owner)
    get dashboard_pwa_path(site_id: site.id)
    assert_response :success
    assert_select "h1", "PWA Administration"
    assert_select "aside.dd-sidebar a[href=?]", dashboard_pwa_path, text: /PWA Administration/
    patch dashboard_pwa_path(site_id: site.id), params: {application: {name: "Client-owned PWA", lock_version: site.pwa_application.lock_version}}
    assert_response :redirect
    assert_equal "Client-owned PWA", site.reload.pwa_application.name
    assert_equal "client", owner.reload.role
  end
  test "platform administrator retains all sites while another client is denied" do
    owner = actor
    stranger = actor
    site = DymondSite::Site.create!(name: "Private application", host: "pwa-#{SecureRandom.hex(6)}.example.test", tenant: owner)
    login(stranger)
    get dashboard_pwa_path(site_id: site.id)
    assert_response :not_found
    login(actor("super_admin"))
    get dashboard_pwa_path(site_id: site.id, section: "settings")
    assert_response :success
    assert_select "aside.dd-sidebar a[href=?][aria-current=page]", dashboard_pwa_path, text: /PWA Administration/
  end
  test "platform administrator can repair a legacy hostname from the dashboard" do
    super_admin = actor("super_admin")
    host! "repair-#{SecureRandom.hex(6)}.example.test"
    site = DymondSite::Site.create!(name: "Imported application", host: "192.168.64.2", tenant: super_admin)
    application_id = site.pwa_application.id
    login(super_admin)
    get dashboard_pwa_path(site_id: site.id)
    assert_response :success
    assert_select "form[action=?]", dashboard_pwa_hostname_path(site_id: site.id)
    post dashboard_pwa_hostname_path(site_id: site.id), params: {expected_host: "192.168.64.2"}
    assert_response :redirect
    assert_equal request.host, site.reload.host
    assert_equal application_id, site.pwa_application.id
    assert_equal "website.hostname.repaired", site.pwa_admin_events.last.action
  end

end
