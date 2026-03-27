require "application_system_test_case"

class StorylineWorldCommunitiesTest < ApplicationSystemTestCase
  setup do
    @storyline_world_community = storyline_world_communities(:one)
  end

  test "visiting the index" do
    visit storyline_world_communities_url
    assert_selector "h1", text: "Storyline world communities"
  end

  test "should create storyline world community" do
    visit storyline_world_communities_url
    click_on "New storyline world community"

    click_on "Create Storyline world community"

    assert_text "Storyline world community was successfully created"
    click_on "Back"
  end

  test "should update Storyline world community" do
    visit storyline_world_community_url(@storyline_world_community)
    click_on "Edit this storyline world community", match: :first

    click_on "Update Storyline world community"

    assert_text "Storyline world community was successfully updated"
    click_on "Back"
  end

  test "should destroy Storyline world community" do
    visit storyline_world_community_url(@storyline_world_community)
    click_on "Destroy this storyline world community", match: :first

    assert_text "Storyline world community was successfully destroyed"
  end
end
