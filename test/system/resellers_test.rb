require "application_system_test_case"

class ResellersTest < ApplicationSystemTestCase
  setup do
    @reseller = resellers(:one)
  end

  test "visiting the index" do
    visit resellers_url
    assert_selector "h1", text: "Resellers"
  end

  test "should create reseller" do
    visit resellers_url
    click_on "New reseller"

    click_on "Create Reseller"

    assert_text "Reseller was successfully created"
    click_on "Back"
  end

  test "should update Reseller" do
    visit reseller_url(@reseller)
    click_on "Edit this reseller", match: :first

    click_on "Update Reseller"

    assert_text "Reseller was successfully updated"
    click_on "Back"
  end

  test "should destroy Reseller" do
    visit reseller_url(@reseller)
    click_on "Destroy this reseller", match: :first

    assert_text "Reseller was successfully destroyed"
  end
end
