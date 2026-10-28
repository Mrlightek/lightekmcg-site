require "test_helper"

class LightekCommerceSectionsTest < ActiveSupport::TestCase
  test "product grid is an editable Dymond Site section" do
    entry = LightekDesign::Catalog.section_definition("lightek_product_grid")
    assert_equal "lightek_product_grid", entry.fetch("kind")
    assert_equal %w[heading intro], entry.fetch("fields").map { |field| field.fetch("name") }
  end
end
