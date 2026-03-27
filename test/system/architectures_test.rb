require "application_system_test_case"

class ArchitecturesTest < ApplicationSystemTestCase
  setup do
    @architecture = architectures(:one)
  end

  test "visiting the index" do
    visit architectures_url
    assert_selector "h1", text: "Architectures"
  end

  test "should create architecture" do
    visit architectures_url
    click_on "New architecture"

    click_on "Create Architecture"

    assert_text "Architecture was successfully created"
    click_on "Back"
  end

  test "should update Architecture" do
    visit architecture_url(@architecture)
    click_on "Edit this architecture", match: :first

    click_on "Update Architecture"

    assert_text "Architecture was successfully updated"
    click_on "Back"
  end

  test "should destroy Architecture" do
    visit architecture_url(@architecture)
    click_on "Destroy this architecture", match: :first

    assert_text "Architecture was successfully destroyed"
  end
end
