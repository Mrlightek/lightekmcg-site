# frozen_string_literal: true
require "test_helper"
class SettingsOrganizationTest < ActionDispatch::IntegrationTest
  def actor(role = "admin")
    User.create!(first_name: "Settings", last_name: "Test", role: role,
      email_address: "settings-#{SecureRandom.hex(8)}@example.test", password: "Settings-acceptance-2026!")
  end
  def login(user)
    post "/session", params: {email_address: user.email_address, password: "Settings-acceptance-2026!"}
    assert_response :redirect
  end
  def website(user, name = "Ocatvia")
    DymondSite::Site.create!(name: name, host: "settings-#{SecureRandom.hex(5)}.example.test", tenant: user)
  end
  test "anonymous settings requests require sign in" do
    get "/dashboard/settings"
    assert_response :redirect
    get "/dashboard/website/settings"
    assert_response :redirect
  end
  test "settings home groups controls with clear descriptions" do
    login(actor("super_admin"))
    get "/dashboard/settings"
    assert_response :success
    assert_select "h1", "Settings"
    assert_select "h2", "Website"
    assert_select "h2", "Dashboard & branding"
    assert_select "a[href='/dashboard/website/settings']", text: /Website name/
  end
  test "owner can rename only the display name" do
    user = actor; site = website(user); login(user)
    patch "/dashboard/website/settings", params: {site_id: site.id, website: {name: " Octavia ", host: "evil.example", tenant_id: actor.id}}
    assert_response :redirect
    assert_equal "Octavia", site.reload.name
    assert_match(/settings-/, site.host)
    assert_equal user.id, site.tenant_id
  end
  test "blank name does not change persisted name" do
    user = actor; site = website(user); login(user)
    patch "/dashboard/website/settings", params: {site_id: site.id, website: {name: " "}}
    assert_response :unprocessable_entity
    assert_equal "Ocatvia", site.reload.name
    assert_select "[role=alert]"
  end
  test "another admin cannot edit a foreign website" do
    site = website(actor); login(actor)
    patch "/dashboard/website/settings", params: {site_id: site.id, website: {name: "Wrong"}}
    assert_response :not_found
    assert_equal "Ocatvia", site.reload.name
  end
  test "client is denied settings access" do
    login(actor("client"))
    get "/dashboard/settings"
    assert_response :forbidden
    get "/dashboard/website/settings"
    assert_response :forbidden
  end
  test "multiple websites require selection without exact hostname" do
    user = actor; website(user); website(user, "Second"); login(user)
    get "/dashboard/website/settings"
    assert_response :success
    assert_select "select[name=site_id]"
    assert_select "input[name='website[name]']", count: 0
  end
  test "rename updates matching hero labels and preserves custom text" do
    user = actor; site = website(user)
    page = site.pages.create!(title: "Home", slug: "home")
    matching = page.sections.create!(kind: "hero", data: {"eyebrow" => "OCATVIA", "heading" => "Media server"})
    custom = page.sections.create!(kind: "hero", data: {"eyebrow" => "Independent media"})
    login(user)
    patch "/dashboard/website/settings", params: {site_id: site.id, website: {name: "Octavia"}}
    assert_response :redirect
    assert_equal "Octavia", matching.reload.data["eyebrow"]
    assert_equal "Media server", matching.data["heading"]
    assert_equal "Independent media", custom.reload.data["eyebrow"]
  end
  test "ordinary admin cannot mutate platform settings through old endpoint" do
    login(actor)
    patch "/dashboard/settings", params: {app_config: {app_name: "Wrong"}}
    assert_response :forbidden
  end
  test "super admin can manage a selected website" do
    site = website(actor); login(actor("super_admin"))
    get "/dashboard/website/settings", params: {site_id: site.id}
    assert_response :success
    patch "/dashboard/website/settings", params: {site_id: site.id, website: {name: "Octavia"}}
    assert_response :redirect
    assert_equal "Octavia", site.reload.name
  end
  test "website name form enforces CSRF protection" do
    user = actor; site = website(user); login(user)
    controller = Dashboard::WebsiteSettingsController
    previous = controller.allow_forgery_protection
    controller.allow_forgery_protection = true
    get "/dashboard/website/settings", params: {site_id: site.id}
    token = css_select("form[action*='/dashboard/website/settings'] input[name=authenticity_token]").first&.[]("value")
    assert token.present?
    rejected = false
    begin
      patch "/dashboard/website/settings", params: {site_id: site.id, website: {name: "Wrong"}}
      rejected = response.status == 422
    rescue ActionController::InvalidAuthenticityToken
      rejected = true
    end
    assert rejected, "A request without a CSRF token must be rejected"
    assert_equal "Ocatvia", site.reload.name
    get "/dashboard/website/settings", params: {site_id: site.id}
    assert_response :success
    token = css_select("form[action*='/dashboard/website/settings'] input[name=authenticity_token]").first&.[]("value")
    assert token.present?
    patch "/dashboard/website/settings", params: {site_id: site.id, authenticity_token: token, website: {name: "Octavia"}}
    assert_response :redirect
    assert_equal "Octavia", site.reload.name
  ensure
    controller.allow_forgery_protection = previous if controller
  end

  test "super admin platform settings save through the existing settings assembler" do
    login(actor("super_admin"))
    patch "/dashboard/settings/general", params: {app_config: {app_name: "Octavia Control Panel", tagline: "Independent media", unexpected_key: "ignored"}}
    assert_response :redirect
    assert_redirected_to "/dashboard/settings/general"
    saved = DymondDash::AppConfig.find_by!(app_name: "Octavia Control Panel")
    assert_equal "Octavia Control Panel", saved.app_name
    assert_equal "Independent media", saved.tagline
  end

end
