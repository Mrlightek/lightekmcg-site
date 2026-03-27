require "test_helper"

class StorylineWorldCommunitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @storyline_world_community = storyline_world_communities(:one)
  end

  test "should get index" do
    get storyline_world_communities_url
    assert_response :success
  end

  test "should get new" do
    get new_storyline_world_community_url
    assert_response :success
  end

  test "should create storyline_world_community" do
    assert_difference("StorylineWorldCommunity.count") do
      post storyline_world_communities_url, params: { storyline_world_community: {} }
    end

    assert_redirected_to storyline_world_community_url(StorylineWorldCommunity.last)
  end

  test "should show storyline_world_community" do
    get storyline_world_community_url(@storyline_world_community)
    assert_response :success
  end

  test "should get edit" do
    get edit_storyline_world_community_url(@storyline_world_community)
    assert_response :success
  end

  test "should update storyline_world_community" do
    patch storyline_world_community_url(@storyline_world_community), params: { storyline_world_community: {} }
    assert_redirected_to storyline_world_community_url(@storyline_world_community)
  end

  test "should destroy storyline_world_community" do
    assert_difference("StorylineWorldCommunity.count", -1) do
      delete storyline_world_community_url(@storyline_world_community)
    end

    assert_redirected_to storyline_world_communities_url
  end
end
