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
  end
end
