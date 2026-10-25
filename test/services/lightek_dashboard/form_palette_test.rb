require "test_helper"
class LightekDashboardFormPaletteTest < ActiveSupport::TestCase
  test "button labels have at least AA contrast against supported accent values" do
    %w[#000000 #ffffff #C4952A #00c9da #6750a4 #edf2f7 #777777 #123 #abc].each do |accent|
      value = LightekDashboard::FormPalette.luminance(accent)
      text = LightekDashboard::FormPalette.luminance(LightekDashboard::FormPalette.foreground(accent))
      assert_operator((([value,text].max+0.05)/([value,text].min+0.05)), :>=, 4.5, accent)
    end
  end
  test "native controls follow light and dark backgrounds" do
    assert_equal "light", LightekDashboard::FormPalette.scheme("#ffffff")
    assert_equal "dark", LightekDashboard::FormPalette.scheme("#111318")
    assert_in_delta 1, LightekDashboard::FormPalette.luminance("rgb(255, 255, 255)"), 0.0001
  end
  test "unsupported values never become injected style content" do
    assert_equal "var(--dd-text-primary)", LightekDashboard::FormPalette.foreground("</style>")
    assert_equal "dark", LightekDashboard::FormPalette.scheme(nil)
  end
end
