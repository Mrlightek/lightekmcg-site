require "application_system_test_case"

class StorylineWorldForgesTest < ApplicationSystemTestCase
  setup do
    @storyline_world_forge = storyline_world_forges(:one)
  end

  test "visiting the index" do
    visit storyline_world_forges_url
    assert_selector "h1", text: "Storyline world forges"
  end

  test "should create storyline world forge" do
    visit storyline_world_forges_url
    click_on "New storyline world forge"

    click_on "Create Storyline world forge"

    assert_text "Storyline world forge was successfully created"
    click_on "Back"
  end

  test "should update Storyline world forge" do
    visit storyline_world_forge_url(@storyline_world_forge)
    click_on "Edit this storyline world forge", match: :first

    click_on "Update Storyline world forge"

    assert_text "Storyline world forge was successfully updated"
    click_on "Back"
  end

  test "should destroy Storyline world forge" do
    visit storyline_world_forge_url(@storyline_world_forge)
    click_on "Destroy this storyline world forge", match: :first

    assert_text "Storyline world forge was successfully destroyed"
  end
end
