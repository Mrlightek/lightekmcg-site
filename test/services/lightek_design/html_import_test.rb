require "test_helper"
class LightekDesignHtmlImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  def setup
    LightekDesign::StudioContext.reset
    @user = User.create!(first_name: "Import", last_name: "Owner", role: "admin", email_address: "import-#{SecureRandom.hex(6)}@example.test", password: "Import-testing-2026!")
    @site = DymondSite::Site.create!(name: "Import site", host: "import-#{SecureRandom.hex(6)}.example.test", tenant: @user)
  end
  def upload
    fixture_file_upload("website_designs/lightek_website.html", "text/html")
  end
  test "queued source becomes a library release and draft page once" do
    record = LightekDesign::HtmlImport.enqueue!(user: @user, site: @site, html_file: upload, create_page: true)
    assert_equal "queued", record.settings.dig("html_import", "status")
    original = record.settings.dig("html_import", "html")
    assert_includes original, "<script>"
    LightekDesign::HtmlImportJob.perform_now(record.id)
    meta = record.reload.settings.fetch("html_import")
    assert_equal "complete", meta["status"]
    assert_equal original, meta["html"]
    workspace = LightekDesign::StudioDocument.find_for!(meta["document_id"], @user)
    assert workspace
    page = @site.pages.find(meta["page_id"])
    refute page.published?
    assert_operator page.sections.count, :>, 6
    count = DymondSite::SiteTemplate.count
    LightekDesign::HtmlImportJob.perform_now(record.id)
    assert_equal count, DymondSite::SiteTemplate.count
    assert_equal 1, @site.pages.count
    assert_nil @site.reload.active_template_id
  end
  test "a revoked site owner cannot complete an import" do
    record = LightekDesign::HtmlImport.enqueue!(user: @user, site: @site, html_file: upload, create_page: true)
    @site.update!(tenant: nil)
    LightekDesign::HtmlImportJob.perform_now(record.id)
    assert_equal "failed", record.reload.settings.dig("html_import", "status")
    assert_equal 0, @site.pages.count
  end
  test "bad input records failure without partial workspace or page" do
    record = LightekDesign::HtmlImport.enqueue!(user: @user, site: @site, html_file: upload, create_page: true, product_selector: "[")
    count = DymondSite::SiteTemplate.count
    LightekDesign::HtmlImportJob.perform_now(record.id)
    assert_equal "failed", record.reload.settings.dig("html_import", "status")
    assert_equal count, DymondSite::SiteTemplate.count
    assert_equal 0, @site.pages.count
  end
  test "industry drafts preserve existing pages edits and return the same shop" do
    first = LightekCommerce::IndustryStarters.install!(site: @site, industry: "beauty", user: @user)
    assert_equal 6, first.sections.count
    first.update!(title: "My edits", published: true)
    first.sections.first.update!(data: {"heading" => "Keep my heading"})
    second = LightekCommerce::IndustryStarters.install!(site: @site, industry: "retail", user: @user)
    refute second.published?
    same = LightekCommerce::IndustryStarters.install!(site: @site, industry: "beauty", user: @user)
    assert_equal first.id, same.id
    assert_equal "My edits", same.title
    assert_equal "Keep my heading", same.sections.first.data["heading"]
    assert_equal 2, @site.pages.count
  end
end
