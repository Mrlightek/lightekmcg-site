require "test_helper"

class StorylineArenasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @storyline_arena = storyline_arenas(:one)
  end

  test "should get index" do
    get storyline_arenas_url
    assert_response :success
  end

  test "should get new" do
    get new_storyline_arena_url
    assert_response :success
  end

  test "should create storyline_arena" do
    assert_difference("StorylineArena.count") do
      post storyline_arenas_url, params: { storyline_arena: {} }
    end

    assert_redirected_to storyline_arena_url(StorylineArena.last)
  end

  test "should show storyline_arena" do
    get storyline_arena_url(@storyline_arena)
    assert_response :success
  end

  test "should get edit" do
    get edit_storyline_arena_url(@storyline_arena)
    assert_response :success
  end

  test "should update storyline_arena" do
    patch storyline_arena_url(@storyline_arena), params: { storyline_arena: {} }
    assert_redirected_to storyline_arena_url(@storyline_arena)
  end

  test "should destroy storyline_arena" do
    assert_difference("StorylineArena.count", -1) do
      delete storyline_arena_url(@storyline_arena)
    end

    assert_redirected_to storyline_arenas_url
  end
end
