require "test_helper"
class LightekDesignFontsTest < ActiveSupport::TestCase
  test "Google stylesheet uses selected families once and a readable loading fallback" do
    url=LightekDesign::Fonts.stylesheet(["Inter", '"Source Serif 4", Georgia, serif', "Inter"])
    parsed=URI.parse(url)
    assert_equal "fonts.googleapis.com", parsed.host
    pairs=URI.decode_www_form(parsed.query)
    assert_equal 2,pairs.count{|key,_|key=="family"}
    assert_includes pairs,["display","swap"]
    assert_includes pairs,["family","Inter:wght@400;500;600;700"]
  end
  test "system fonts produce no Google request" do
    assert_nil LightekDesign::Fonts.stylesheet(["system-ui, sans-serif","Georgia, serif","monospace"])
  end
  test "any valid Google family is supported beyond suggestions" do
    assert_includes URI.decode_www_form(URI.parse(LightekDesign::Fonts.stylesheet(["Noto Sans Armenian"])).query),["family","Noto Sans Armenian"]
    assert_operator LightekDesign::Fonts.families.length,:>=,100
  end
  test "invalid font values cannot inject CSS or stylesheet parameters" do
    ['</style><script>alert(1)</script>', 'Inter; color:red', 'Inter&family=Evil', 'url(https://example.test)'].each do |value|
      assert_nil LightekDesign::Fonts.css_stack(value)
      assert_nil LightekDesign::Fonts.stylesheet([value])
    end
  end
  test "existing CSS stacks retain fallback order" do
    assert_equal '"Source Serif 4", Georgia, serif, sans-serif',LightekDesign::Fonts.css_stack('"Source Serif 4", Georgia, serif')
    assert_nil LightekDesign::Fonts.css_stack("")
  end
  test "Google display names resolve to their loadable Playwrite families" do
    assert_equal "Playwrite AR Guides",LightekDesign::Fonts.google_family("Playwrite Argentina Guides")
    assert_equal '"Playwrite AR Guides", sans-serif',LightekDesign::Fonts.css_stack("Playwrite Argentina Guides")
    assert_includes URI.decode_www_form(URI.parse(LightekDesign::Fonts.stylesheet(["Playwrite Argentina Guides"])).query),["family","Playwrite AR Guides"]
    assert_equal "Playwrite AR",LightekDesign::Fonts.google_family("Playwrite Argentina")
  end

end
