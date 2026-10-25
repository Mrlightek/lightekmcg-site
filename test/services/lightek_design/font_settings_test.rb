require "test_helper"
class LightekDesignFontSettingsTest < ActiveSupport::TestCase
  test "template settings save and reload all three font choices" do
    values = DymondDash::TemplateSettingsAssembler.build({"font_sans"=>"Barlow", "font_heading"=>"Barlow Condensed", "font_mono"=>"DM Mono"})
    template = DymondSite::SiteTemplate.create!(name: "Font acceptance #{SecureRandom.hex(6)}", settings: values)
    tokens = template.reload.tokens
    assert_equal "Barlow", tokens["font_sans"]
    assert_equal "Barlow Condensed", tokens["font_heading"]
    assert_equal "DM Mono", tokens["font_mono"]
  end
  test "template validation rejects font declarations containing style instructions" do
    template = DymondSite::SiteTemplate.new(name: "Font validation #{SecureRandom.hex(6)}", settings: {"tokens"=>{"font_heading"=>"Inter; color:red"}})
    refute template.valid?
    assert_includes template.errors.full_messages.join(" "), "Enter font family names"
  end
end
