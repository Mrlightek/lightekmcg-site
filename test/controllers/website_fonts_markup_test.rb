# frozen_string_literal: true
require "test_helper"
class WebsiteFontsMarkupTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  def probe(body, content_type: "text/html")
    controller = Class.new(ActionController::Base) { include LightekDesign::WebsiteFonts }.new
    controller.instance_variable_set(:@site, Object.new)
    controller.instance_variable_set(:@page, Object.new)
    controller.response = ActionDispatch::Response.new(200, {"Content-Type" => content_type, "Content-Length" => body.bytesize.to_s}, body)
    controller
  end
  test "rendered safe buffer typography retains a real closing head tag" do
    controller = probe('<!doctype html><html><head><title>Customer</title></head><body><h1>Welcome</h1></body></html>')
    typography = '<style id="lightek-website-typography">body{font-family:Georgia}</style>'.html_safe
    controller.stub(:render_to_string, ->(**) { typography }) do
      controller.send(:lightek_append_website_fonts)
    end
    html = controller.response.body
    document = Nokogiri::HTML(html)
    assert_equal 1, html.scan("</head>").length
    refute_includes html, "&lt;/head&gt;"
    refute_includes document.at_css("body").text, "</head>"
    assert document.at_css("head style#lightek-website-typography")
    assert_equal "Welcome", document.at_css("body h1").text
    assert_nil controller.response.headers["Content-Length"]
  end
  test "existing typography is not inserted twice" do
    html = '<html><head><style id="lightek-website-typography">body{font-family:Georgia}</style></head><body>Customer</body></html>'
    controller = probe(html)
    controller.stub(:render_to_string, ->(**) { flunk "Typography was rendered twice" }) do
      controller.send(:lightek_append_website_fonts)
    end
    assert_equal html, controller.response.body
  end
  test "fragments and non HTML responses are left intact" do
    [['<section>Customer</section>', "text/html"], ['{"page":"</head>"}', "application/json"]].each do |html, type|
      controller = probe(html, content_type: type)
      controller.stub(:render_to_string, ->(**) { flunk "Non-document response was modified" }) do
        controller.send(:lightek_append_website_fonts)
      end
      assert_equal html, controller.response.body
    end
  end
end
