# Run with Ruby + active_support, nokogiri, crass and minitest; no app boot required.
require "logger"
require "json"
require "securerandom"
require "active_support"
require "active_support/core_ext"
require "minitest/autorun"
require_relative "../../app/services/lightek_design/catalog"
require_relative "../../app/services/lightek_design/fonts"
require_relative "../../app/services/lightek_design/studio_blocks"
require_relative "../../app/services/lightek_design/studio_document"
require_relative "../../app/services/lightek_design/commerce_sections"
require_relative "../../app/services/lightek_design/html_document"
require_relative "../../app/services/lightek_commerce/industry_starters"
module LightekDesign
  module Catalog
    def self.builtin_designs = {}
  end
end
module DymondSite
  module SectionRegistry
    def self.find(key)
      return unless key == "lightek_product_grid"
      Struct.new(:schema).new(LightekDesign::CommerceSections.definitions.first["fields"])
    end
  end
end

class HtmlDesignChecks < Minitest::Test
  def fixture(name)
    File.read(File.expand_path("../fixtures/files/website_designs/#{name}.html", __dir__))
  end
  def test_attached_corporate_design_becomes_editable_sections
    document, warnings = LightekDesign::HtmlDocument.convert(html: fixture("lightek_website"))
    assert_operator document["sections"].length, :>, 6
    assert document["sections"].all? { |section| section["block"] == "html" }
    assert document["sections"].any? { |section| section["data"]["copy"].any? { |copy| copy.include?("Six fronts") } }
    document["sections"].each do |section|
      data = section["data"]
      refute_match(/<script|onclick=|<form/, data["html"])
      assert_includes LightekDesign::HtmlDocument.shadow_css(data["css"]), ":host"
    end
    assert warnings.any? { |warning| warning.include?("JavaScript") }
  end
  def test_store_dynamic_product_grid_is_mapped_to_live_commerce
    document, = LightekDesign::HtmlDocument.convert(html: fixture("lightek_store"), product_selector: "#grid")
    assert_equal "#05060a", document["tokens"]["color_bg"]
    assert_equal "#00ffff", document["tokens"]["color_primary"]
    products = document["sections"].select { |section| section["source_kind"] == "lightek_product_grid" }
    assert_equal 1, products.length
    assert document["sections"].any? { |section| section["data"].fetch("copy", []).any? { |copy| copy.include?("Hardware") } }
  end
  def test_editable_copy_images_and_links_keep_markup
    doc, = LightekDesign::HtmlDocument.convert(html: '<section><h2>Hello <em>world</em></h2><a href="/shop">Shop</a><img src="https://example.test/one.png"></section>')
    data = doc["sections"].first["data"]
    data["copy"][0] = "New <script>title</script> "
    data["links"][0] = "javascript:alert(1)"
    data["images"][0] = "https://example.test/two.png"
    html = LightekDesign::HtmlDocument.render_html(data)
    assert_includes html, "&lt;script&gt;"
    assert_includes html, '<em>world</em>'
    assert_includes html, 'href="#"'
    assert_includes html, 'two.png'
  end
  def test_css_preserves_media_variables_and_keyframes_and_rejects_active_content
    css = ':root{--ink:#123456}body{color:var(--ink)}@media(max-width:600px){body{padding:4px}}@keyframes spin{from{opacity:0}to{opacity:1}}@import "https://evil.test/x.css";a{background:url("javascript:alert(1)");color:red}p{content:"</style><script>"}'
    result = LightekDesign::HtmlDocument.shadow_css(css)
    assert_includes result, '--ink:#123456'
    assert_includes result, '.li-body{color:var(--ink);}'
    assert_includes result, '@media'
    assert_includes result, '@keyframes spin'
    refute_includes result, '@import'
    refute_includes result, 'javascript:'
    refute_includes result, '</style>'
  end
  def test_html_sanitization_and_font_link_validation
    html = '<svg><use href="javascript:alert(1)"/><script>alert(1)</script></svg><img src="x" onerror="bad()"><iframe src="https://evil.test"></iframe><a href="java&#x73;cript:bad()">Bad</a>'
    result = LightekDesign::HtmlDocument.clean_html(html)
    refute_match(/javascript:|onerror|<script|<iframe/, result)
    data = LightekDesign::HtmlDocument.normalize_data({"font_stylesheets" => "https://fonts.googleapis.com.evil.test/css\nhttps://fonts.googleapis.com/css2?family=Inter"})
    assert_equal "https://fonts.googleapis.com/css2?family=Inter", data["font_stylesheets"]
  end
  def test_oversized_empty_and_invalid_inputs
    assert_raises(ArgumentError) { LightekDesign::HtmlDocument.convert(html: " " * 500_001) }
    assert_raises(ArgumentError) { LightekDesign::HtmlDocument.convert(html: "<script>x</script>") }
    assert_raises(ArgumentError) { LightekDesign::HtmlDocument.convert(html: "<section>Hello</section>", product_selector: "[") }
  end
  def test_all_five_industries_have_complete_distinct_editable_layouts
    site = Struct.new(:id, :name).new(12, "Client Boutique")
    palettes = []
    LightekCommerce::IndustryStarters::INDUSTRIES.each_key do |industry|
      doc = LightekDesign::StudioDocument.normalize(LightekCommerce::IndustryStarters.document(industry, site: site))
      assert_equal 6, doc["sections"].size
      assert_equal 1, doc["sections"].count { |section| section["source_kind"] == "lightek_product_grid" }
      assert_equal "products", doc["sections"][2]["anchor"]
      assert_includes doc["sections"][0]["data"]["eyebrow"], site.name
      assert File.exist?(File.expand_path("../../public/lightek/commerce/#{industry}.svg", __dir__))
      palettes << doc["tokens"]["color_primary"]
    end
    assert_equal 5, palettes.uniq.size
  end
end
