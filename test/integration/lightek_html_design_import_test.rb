require "test_helper"
class LightekHtmlDesignImportTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  def actor
    User.create!(first_name: "HTML", last_name: "Designer", role: "admin", email_address: "html-#{SecureRandom.hex(6)}@example.test", password: "HTML-testing-2026!")
  end
  def login(user)
    post "/session", params: {email_address: user.email_address, password: "HTML-testing-2026!"}
  end
  def website(user)
    DymondSite::Site.create!(name: "Design shop", host: "shop-#{SecureRandom.hex(6)}.example.test", tenant: user)
  end
  test "upload requires sign in and selected website ownership" do
    owner = actor; site = website(owner)
    post upload_dashboard_website_designs_path, params: {site_id: site.id}
    assert_response :redirect
    login(actor)
    post upload_dashboard_website_designs_path, params: {site_id: site.id}
    assert_response :not_found
    assert_empty site.pages
  end
  test "selected site has upload UI and a job produces an owned editable design" do
    user = actor; site = website(user); login(user)
    get dashboard_website_designs_path(site_id: site.id)
    assert_response :success
    assert_select 'input[type="file"][name="html_file"]'
    perform_enqueued_jobs do
      post upload_dashboard_website_designs_path, params: {site_id: site.id, name: "Uploaded design", html_file: fixture_file_upload("website_designs/lightek_website.html", "text/html"), create_page: "1"}
    end
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_select "h3", text: "Uploaded design · Complete"
    refute site.pages.first.published?
  end
  test "industry previews render complete layouts without creating records" do
    user = actor; site = website(user); login(user)
    assert_no_difference ["DymondSite::Page.count", "DymondSite::SiteTemplate.count"] do
      get preview_dashboard_commerce_industry_path(site_id: site.id, industry: "beauty")
    end
    assert_response :success
    assert_select "h1", text: "A little ritual. A lot of you."
    assert_select "[data-studio-section]", count: 6
  end
  test "published industry shop renders live products and draft replacement retains live shop" do
    user = actor; site = website(user)
    page = LightekCommerce::IndustryStarters.install!(site: site, industry: "retail", user: user)
    page.update!(published: true)
    LightekCommerce::IndustryStarters.install!(site: site, industry: "beauty", user: user)
    get commerce_shop_path(site_id: site.id)
    assert_response :success
    assert_select "h1", text: "Everyday pieces. Uncommon style."
    assert_select "#cart", count: 1
    assert_select '[data-studio-section]', count: 6
  end
end
