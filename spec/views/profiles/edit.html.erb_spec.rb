require 'rails_helper'

RSpec.describe "profiles/edit", type: :view do
  let(:profile) {
    Profile.create!(
      user: nil,
      bio: "MyText"
    )
  }

  before(:each) do
    assign(:profile, profile)
  end

  it "renders the edit profile form" do
    render

    assert_select "form[action=?][method=?]", profile_path(profile), "post" do

      assert_select "input[name=?]", "profile[user_id]"

      assert_select "textarea[name=?]", "profile[bio]"
    end
  end
end
