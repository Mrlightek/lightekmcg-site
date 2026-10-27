require "test_helper"

class CommercialControllerTest < ActionDispatch::IntegrationTest
  test "public commercial portfolio is available" do
    get "/commercial"
    assert_response :success
    assert_select "h1", text: /infrastructure behind digital independence/i
    assert_select "a[href='/commercial/enterprise']"
  end

  test "enterprise offer is available" do
    get "/commercial/enterprise"
    assert_response :success
    assert_select "h1", text: /your business/i
    assert_select "a[href='/contact']"
  end

  test "media portfolio is available" do
    get "/commercial/media"
    assert_response :success
    assert_select "h1", text: /stories deserve/i
  end
end
