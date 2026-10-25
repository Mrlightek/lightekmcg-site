require "test_helper"
class LightekDesignWebsiteDesignsTest < ActiveSupport::TestCase
  def website
    DymondSite::Site.create!(name: "Design test #{SecureRandom.hex(6)}", host: "design-#{SecureRandom.hex(6)}.example.test")
  end

  test "applying a design preserves pages sections and publication" do
    site = website
    page = site.pages.create!(title: "Existing", slug: "home", published: true)
    section = page.sections.create!(kind: "hero", data: {"heading" => "Keep this"})
    LightekDesign::WebsiteDesigns.apply!(site: site, design: "vinylctrl")
    assert page.reload.published?
    assert_equal [page.id], site.pages.pluck(:id)
    assert_equal({"heading" => "Keep this"}, section.reload.data)
    assert_equal "vinylctrl", LightekDesign::Catalog.design_for(site.reload)
  end

  test "imports are draft idempotent and preserve renamed edited published pages" do
    site = website
    page = LightekDesign::WebsiteDesigns.import!(site: site, design: "ybnc")
    refute page.published?
    assert_equal 9, page.sections.count
    page.update!(slug: "our-movement", published: true)
    section = page.sections.first
    section.update!(data: {"text_1" => "Client copy"})
    same = LightekDesign::WebsiteDesigns.import!(site: site, design: "ybnc")
    assert_equal page.id, same.id
    assert same.published?
    assert_equal "Client copy", section.reload.data["text_1"]
    assert_nil site.reload.active_template_id
  end

  test "a preexisting starter slug is never overwritten" do
    site = website
    existing = site.pages.create!(title: "Mine", slug: "vinylctrl-starter", published: true)
    imported = LightekDesign::WebsiteDesigns.import!(site: site, design: "vinylctrl")
    assert_equal "vinylctrl-starter-2", imported.slug
    assert_equal "Mine", existing.reload.title
    assert existing.published?
    assert_equal 7, imported.sections.count
  end

  test "font customization belongs to one website and survives switching" do
    first, second = website, website
    [first, second].each { |site| LightekDesign::WebsiteDesigns.apply!(site: site, design: "vinylctrl") }
    refute_equal first.active_template_id, second.active_template_id
    LightekDesign::WebsiteDesigns.save_fonts!(site: first, values: {"font_heading" => "Playwrite AR Guides"})
    assert_equal "Barlow Condensed", second.reload.active_template.tokens["font_heading"]
    LightekDesign::WebsiteDesigns.apply!(site: first, design: "ybnc")
    LightekDesign::WebsiteDesigns.apply!(site: first, design: "vinylctrl")
    assert_equal "Playwrite AR Guides", first.reload.active_template.tokens["font_heading"]
    assert_equal first.id, first.active_template.settings["lightek_site_id"]
  end

  test "invalid font input is rejected without writing" do
    site = website
    LightekDesign::WebsiteDesigns.apply!(site: site, design: "ybnc")
    before = site.active_template.settings.deep_dup
    assert_raises(ArgumentError) { LightekDesign::WebsiteDesigns.save_fonts!(site: site, values: {"font_heading" => "</style><script>alert(1)</script>"}) }
    assert_equal before, site.active_template.reload.settings
  end

  test "catalog registry and URL handling preserve safety boundaries" do
    LightekDesign::Catalog.section_definitions.each do |entry|
      klass = DymondSite::SectionRegistry.find(entry["kind"])
      assert klass
      assert_equal entry["data"].keys.sort, klass.schema.map { |field| field[:name].to_s }.sort
    end
    ["javascript:alert(1)", "//evil.example", "\\evil.example", "data:text/html,test"].each do |url|
      assert_equal "#", LightekDesign::Catalog.safe_url(url)
    end
    assert_equal "/contact", LightekDesign::Catalog.safe_url("/contact")
    assert_equal "#mission", LightekDesign::Catalog.safe_url("#mission")
  end
end
