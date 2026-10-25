require "test_helper"
class LightekWebsiteDesignsTest < ActionDispatch::IntegrationTest
  def actor(role = "admin")
    User.create!(first_name: "Design", last_name: "Test", role: role,
      email_address: "design-#{SecureRandom.hex(8)}@example.test", password: "Design-acceptance-2026!")
  end
  def website(user)
    DymondSite::Site.create!(name: "Design website", host: "design-#{SecureRandom.hex(6)}.example.test", tenant: user)
  end
  def login(user)
    post "/session", params: {email_address: user.email_address, password: "Design-acceptance-2026!"}
    assert_response :redirect
  end

  test "anonymous visitors must sign in" do
    get "/dashboard/website/designs"
    assert_response :redirect
  end

  test "owner can preview apply and import without publishing" do
    user = actor; site = website(user); login(user)
    get "/dashboard/website/designs", params: {site_id: site.id}
    assert_response :success
    assert_select "h1", "Website designs & fonts"
    get "/dashboard/website/designs/preview", params: {site_id: site.id, design: "ybnc"}
    assert_response :success
    assert_select "[data-design-section]", count: 9
    assert_select "[data-demo-signup] input[disabled]"
    assert_equal 0, site.pages.count
    post "/dashboard/website/designs/apply", params: {site_id: site.id, design: "ybnc"}
    assert_response :redirect
    post "/dashboard/website/designs/import", params: {site_id: site.id, design: "ybnc"}
    assert_response :redirect
    refute site.pages.first.published?
  end

  test "an admin cannot inspect or mutate a foreign website" do
    site = website(actor); login(actor)
    get "/dashboard/website/designs/preview", params: {site_id: site.id, design: "vinylctrl"}
    assert_response :not_found
    post "/dashboard/website/designs/apply", params: {site_id: site.id, design: "vinylctrl"}
    assert_response :not_found
    assert_nil site.reload.active_template_id
    assert_equal 0, site.pages.count
  end

  test "super admin can operate on a selected website" do
    site = website(actor); login(actor("super_admin"))
    post "/dashboard/website/designs/apply", params: {site_id: site.id, design: "vinylctrl"}
    assert_response :redirect
    get "/dashboard/website/designs", params: {site_id: site.id}
    assert_response :success
    assert_select "[data-lightek-font-picker]", count: 3
  end

  test "invalid design does not change a website" do
    user = actor; site = website(user); login(user)
    post "/dashboard/website/designs/apply", params: {site_id: site.id, design: "../../invalid"}
    assert_response :not_found
    assert_nil site.reload.active_template_id
  end
end
