require "application_system_test_case"

class StorylineArenasTest < ApplicationSystemTestCase
  setup do
    @storyline_arena = storyline_arenas(:one)
  end

  test "visiting the index" do
    visit storyline_arenas_url
    assert_selector "h1", text: "Storyline arenas"
  end

  test "should create storyline arena" do
    visit storyline_arenas_url
    click_on "New storyline arena"

    click_on "Create Storyline arena"

    assert_text "Storyline arena was successfully created"
    click_on "Back"
  end

  test "should update Storyline arena" do
    visit storyline_arena_url(@storyline_arena)
    click_on "Edit this storyline arena", match: :first

    click_on "Update Storyline arena"

    assert_text "Storyline arena was successfully updated"
    click_on "Back"
  end

  test "should destroy Storyline arena" do
    visit storyline_arena_url(@storyline_arena)
    click_on "Destroy this storyline arena", match: :first

    assert_text "Storyline arena was successfully destroyed"
  end
end
