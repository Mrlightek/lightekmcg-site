require "test_helper"

class StorylineWorldForgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @storyline_world_forge = storyline_world_forges(:one)
  end

  test "should get index" do
    get storyline_world_forges_url
    assert_response :success
  end

  test "should get new" do
    get new_storyline_world_forge_url
    assert_response :success
  end

  test "should create storyline_world_forge" do
    assert_difference("StorylineWorldForge.count") do
      post storyline_world_forges_url, params: { storyline_world_forge: {} }
    end

    assert_redirected_to storyline_world_forge_url(StorylineWorldForge.last)
  end

  test "should show storyline_world_forge" do
    get storyline_world_forge_url(@storyline_world_forge)
    assert_response :success
  end

  test "should get edit" do
    get edit_storyline_world_forge_url(@storyline_world_forge)
    assert_response :success
  end

  test "should update storyline_world_forge" do
    patch storyline_world_forge_url(@storyline_world_forge), params: { storyline_world_forge: {} }
    assert_redirected_to storyline_world_forge_url(@storyline_world_forge)
  end

  test "should destroy storyline_world_forge" do
    assert_difference("StorylineWorldForge.count", -1) do
      delete storyline_world_forge_url(@storyline_world_forge)
    end

    assert_redirected_to storyline_world_forges_url
  end
end
