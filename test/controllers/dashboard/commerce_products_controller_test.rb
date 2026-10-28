require "test_helper"
class DashboardCommerceProductsControllerTest < ActionDispatch::IntegrationTest
  test "commerce product routes are registered" do
    assert_equal({controller: "dashboard/commerce_products", action: "index"}, Rails.application.routes.recognize_path("/dashboard/commerce/products", method: :get))
  end
end
