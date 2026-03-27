require "test_helper"

class StorylinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @storyline = storylines(:one)
  end

  test "should get index" do
    get storylines_url
    assert_response :success
  end

  test "should get new" do
    get new_storyline_url
    assert_response :success
  end

  test "should create storyline" do
    assert_difference("Storyline.count") do
      post storylines_url, params: { storyline: {} }
    end

    assert_redirected_to storyline_url(Storyline.last)
  end

  test "should show storyline" do
    get storyline_url(@storyline)
    assert_response :success
  end

  test "should get edit" do
    get edit_storyline_url(@storyline)
    assert_response :success
  end

  test "should update storyline" do
    patch storyline_url(@storyline), params: { storyline: {} }
    assert_redirected_to storyline_url(@storyline)
  end

  test "should destroy storyline" do
    assert_difference("Storyline.count", -1) do
      delete storyline_url(@storyline)
    end

    assert_redirected_to storylines_url
  end
end
