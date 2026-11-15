# Export the real Rails views for browser checks without private engine gems.
# Usage: ruby test/support/export_dashboard_forms.rb /tmp/lightek-form-fixtures
require_relative "../standalone/commerce_order_cleanup_test"
require "fileutils"
require Rails.root.join("app/services/lightek_dashboard/appearance_palette").to_s
require Rails.root.join("app/services/lightek_dashboard/form_palette").to_s
fixture = CommerceOrderCleanupHttpTest.new("preview")
fixture.setup
begin
  site = fixture.instance_variable_get(:@site)
  site.update!(name: "Lightek")
  owner = fixture.instance_variable_get(:@operator)
  shop_product = fixture.product(name: "Lightek Managed Application", billing_interval: "one_time")
  paid = fixture.order_for(shop_product)
  paid.update!(status: "paid", paid_at: Time.current)
  2.times do |index|
    record = fixture.order_for(fixture.product(name: index.zero? ? "Creative services" : "Studio membership", billing_interval: "one_time"))
    record.update!(customer_email: "#{index.zero? ? 'alex' : 'taylor'}@example.com")
  end
  orders = fixture.request(:get, "/dashboard/commerce/orders", site_id: site.id)
  raise orders.body unless orders.status == 200
  controller = Dashboard::CommerceOrdersController.new
  controller.set_request!(ActionDispatch::TestRequest.create)
  controller.set_response!(ActionDispatch::TestResponse.new)
  controller.define_singleton_method(:current_user) { owner }
  controller.instance_variable_set(:@site, site)
  controller.instance_variable_set(:@product, shop_product)
  # The host's Active Storage attachment proxy is replaced at this boundary.
  shop_product.define_singleton_method(:photos) { Struct.new(:attached?).new(false) }
  product = controller.view_context.render(partial: "dashboard/commerce_products/form")
  palette = LightekDashboard::AppearancePalette.values(nil)
  theme_partial = Rails.root.join("app/views/dymond_dash/shared/_theme_forms.html.erb").read
  theme_styles = theme_partial.split('<style id="lightek-dashboard-theme-forms">').last.split('</style>').first
  # Render the actual color rules, supplying only the palette normally read from DB.
  colors = palette
  theme_context = Object.new
  theme_context.define_singleton_method(:dashboard_colors) { colors }
  theme_context.define_singleton_method(:accent) { colors.fetch("accent") }
  theme_context.define_singleton_method(:hover) { colors.fetch("accent_hover") }
  theme_context.define_singleton_method(:background) { colors.fetch("input_bg") }
  theme_css = ERB.new(theme_styles).result(theme_context.instance_eval { binding })
  output = File.expand_path(ARGV.shift || "/tmp/lightek-form-fixtures")
  FileUtils.mkdir_p(output)
  File.write(File.join(output, "orders.html"), orders.body)
  File.write(File.join(output, "product.html"), product)
  File.write(File.join(output, "theme.css"), theme_css)
  puts "Exported real Orders and Product form views to #{output}"
ensure
  fixture.teardown
end
