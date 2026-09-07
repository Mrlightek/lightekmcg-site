require 'rails_helper'

RSpec.describe "episodes/new", type: :view do
  before(:each) do
    assign(:episode, Episode.new(
      title: "MyString",
      subtitle: "MyString",
      url: "MyString",
      description: "MyText",
      show_title: "MyString",
      show_description: "MyText"
    ))
  end

  it "renders new episode form" do
    render

    assert_select "form[action=?][method=?]", episodes_path, "post" do

      assert_select "input[name=?]", "episode[title]"

      assert_select "input[name=?]", "episode[subtitle]"

      assert_select "input[name=?]", "episode[url]"

      assert_select "textarea[name=?]", "episode[description]"

      assert_select "input[name=?]", "episode[show_title]"

      assert_select "textarea[name=?]", "episode[show_description]"
    end
  end
end
