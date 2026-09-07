require 'rails_helper'

RSpec.describe "episodes/edit", type: :view do
  let(:episode) {
    Episode.create!(
      title: "MyString",
      subtitle: "MyString",
      url: "MyString",
      description: "MyText",
      show_title: "MyString",
      show_description: "MyText"
    )
  }

  before(:each) do
    assign(:episode, episode)
  end

  it "renders the edit episode form" do
    render

    assert_select "form[action=?][method=?]", episode_path(episode), "post" do

      assert_select "input[name=?]", "episode[title]"

      assert_select "input[name=?]", "episode[subtitle]"

      assert_select "input[name=?]", "episode[url]"

      assert_select "textarea[name=?]", "episode[description]"

      assert_select "input[name=?]", "episode[show_title]"

      assert_select "textarea[name=?]", "episode[show_description]"
    end
  end
end
