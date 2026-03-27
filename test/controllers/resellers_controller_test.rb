require "test_helper"

class ResellersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @reseller = resellers(:one)
  end

  test "should get index" do
    get resellers_url
    assert_response :success
  end

  test "should get new" do
    get new_reseller_url
    assert_response :success
  end

  test "should create reseller" do
    assert_difference("Reseller.count") do
      post resellers_url, params: { reseller: {} }
    end

    assert_redirected_to reseller_url(Reseller.last)
  end

  test "should show reseller" do
    get reseller_url(@reseller)
    assert_response :success
  end

  test "should get edit" do
    get edit_reseller_url(@reseller)
    assert_response :success
  end

  test "should update reseller" do
    patch reseller_url(@reseller), params: { reseller: {} }
    assert_redirected_to reseller_url(@reseller)
  end

  test "should destroy reseller" do
    assert_difference("Reseller.count", -1) do
      delete reseller_url(@reseller)
    end

    assert_redirected_to resellers_url
  end
end
