require "application_system_test_case"

class StorylinesTest < ApplicationSystemTestCase
  setup do
    @storyline = storylines(:one)
  end

  test "visiting the index" do
    visit storylines_url
    assert_selector "h1", text: "Storylines"
  end

  test "should create storyline" do
    visit storylines_url
    click_on "New storyline"

    click_on "Create Storyline"

    assert_text "Storyline was successfully created"
    click_on "Back"
  end

  test "should update Storyline" do
    visit storyline_url(@storyline)
    click_on "Edit this storyline", match: :first

    click_on "Update Storyline"

    assert_text "Storyline was successfully updated"
    click_on "Back"
  end

  test "should destroy Storyline" do
    visit storyline_url(@storyline)
    click_on "Destroy this storyline", match: :first

    assert_text "Storyline was successfully destroyed"
  end
end
