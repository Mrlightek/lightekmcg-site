gem 'minitest', '~> 5.25'
require 'minitest/autorun'
require 'active_support/all'
require_relative '../../app/services/lightek_dashboard/appearance_palette'
require_relative '../../app/services/lightek_dashboard/form_palette'

class DashboardAppearanceTest < Minitest::Test
  Palette = LightekDashboard::AppearancePalette
  Theme = Struct.new(:tokens)

  def test_existing_theme_colors_supply_new_surfaces_without_using_pwa_settings
    theme = Theme.new({'card_bg'=>'#111827', 'text_primary'=>'#f9fafb', 'border'=>'#374151', 'accent'=>'#a78bfa'})
    values = Palette.values(theme)
    assert_equal '#111827', values['page_bg']
    assert_equal '#111827', values['input_bg']
    assert_equal '#f9fafb', values['input_text']
    assert_equal '#374151', values['input_border']
    assert_equal '#a78bfa', values['accent']
  end

  def test_palette_accepts_every_editable_color_and_ignores_unknown_keys
    values = Palette.values(nil).merge('scope'=>'site', 'custom_css'=>'body {display:none}')
    assert_equal Palette::COLORS.keys.sort, Palette.validate!(values).keys.sort
    assert_equal '#2563eb', Palette.validate!(values)['accent']
  end

  def test_invalid_or_incomplete_color_submissions_cannot_be_saved_as_css
    ['red', '#fff', '#123456;display:none', '</style><script>', nil].each do |bad|
      assert_raises(ArgumentError) { Palette.validate!(Palette.values(nil).merge('accent'=>bad)) }
    end
    assert_raises(ArgumentError) { Palette.validate!({'accent'=>'#112233'}) }
  end

  def test_invalid_existing_tokens_cannot_escape_the_style_element
    theme = Theme.new({'accent'=>'</style><script>alert(1)</script>', 'input_bg'=>'url(https://example.com)'})
    assert Palette.values(theme).values.all? { |value| value.match?(/\A#[a-f0-9]{6}\z/i) }
  end

  def test_primary_button_labels_stay_readable_for_light_and_dark_accents
    %w[#ffffff #000000 #2563eb #a78bfa #e8c475].each do |accent|
      a = LightekDashboard::FormPalette.luminance(accent)
      b = LightekDashboard::FormPalette.luminance(LightekDashboard::FormPalette.foreground(accent))
      assert_operator((([a,b].max+0.05)/([a,b].min+0.05)), :>=, 4.5)
    end
  end
end

require 'active_record'
require 'action_controller'
require 'action_controller/test_case'
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.define do
  create_table(:themes) { |t| t.string :name; t.string :scope; t.boolean :preset; t.json :tokens; t.text :custom_css; t.json :templates }
  create_table(:app_configs) { |t| t.integer :theme_id }
end
module DymondTheme
  class Theme < ActiveRecord::Base
    self.table_name = 'themes'
  end
end
module DymondDash
  class AppConfig < ActiveRecord::Base
    self.table_name = 'app_configs'
    belongs_to :theme, class_name: 'DymondTheme::Theme', optional: true
    def self.current = first
  end
end
class ApplicationController < ActionController::Base
  def current_user = Struct.new(:role).new(request.headers['X-Test-Role'])
end
module Dashboard; end
require_relative '../../app/controllers/dashboard/appearance_colors_controller'
class DashboardAppearanceControllerTest < ActionController::TestCase
  tests Dashboard::AppearanceColorsController
  def setup
    DymondDash::AppConfig.delete_all
    DymondTheme::Theme.delete_all
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get '/dashboard/appearance/colors', to: 'dashboard/appearance_colors#show', as: :dashboard_appearance_colors
      patch '/dashboard/appearance/colors', to: 'dashboard/appearance_colors#update'
    end
    @controller.define_singleton_method(:dashboard_appearance_colors_path) { '/dashboard/appearance/colors' }
    # Exercise real request filters and persistence without booting the private engines.
    @controller.define_singleton_method(:render) { |*args, **kwargs| self.status = kwargs[:status] if kwargs[:status]; self.response_body = 'Dashboard palette' }
    @controller.allow_forgery_protection = false
    @request.headers['X-Test-Role'] = 'super_admin'
  end

  def test_save_creates_admin_theme_and_preserves_preset_and_pwa_theme
    preset = DymondTheme::Theme.create!(name: 'Preset', scope: 'admin', preset: true, tokens: {'accent'=>'#111111', 'custom_token'=>'preserved'})
    pwa = DymondTheme::Theme.create!(name: 'PWA', scope: 'pwa', tokens: {'accent'=>'#C4952A'})
    config = DymondDash::AppConfig.create!(theme: preset)
    patch :update, params: {colors: LightekDashboard::AppearancePalette.values(nil).merge('accent'=>'#a78bfa')}
    assert_response :redirect
    saved = config.reload.theme
    assert_equal 'admin', saved.scope
    refute saved.preset
    refute_equal preset.id, saved.id
    assert_equal '#a78bfa', saved.tokens['accent']
    assert_equal 'preserved', saved.tokens['custom_token']
    assert_equal '#111111', preset.reload.tokens['accent']
    assert_equal '#C4952A', pwa.reload.tokens['accent']
  end

  def test_non_operator_cannot_view_or_change_platform_colors
    %w[white_label customer].each do |role|
      @request.headers['X-Test-Role'] = role
      get :show
      assert_response :forbidden
      patch :update, params: {colors: LightekDashboard::AppearancePalette.values(nil)}
      assert_response :forbidden
    end
    assert_equal 0, DymondTheme::Theme.count
  end

  def test_invalid_palette_does_not_replace_active_theme
    theme = DymondTheme::Theme.create!(name:'Current',scope:'admin',tokens:{'accent'=>'#123456'})
    config = DymondDash::AppConfig.create!(theme:theme)
    patch :update, params: {colors: LightekDashboard::AppearancePalette.values(nil).merge('accent'=>'</style>')}
    assert_response :unprocessable_entity
    assert_equal theme.id, config.reload.theme_id
    assert_equal 1, DymondTheme::Theme.count
  end
end
