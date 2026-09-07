require 'rails_helper'

RSpec.describe "shows/new", type: :view do
  before(:each) do
    assign(:show, Show.new(
      title: "MyString",
      network: "MyString",
      episode: nil
    ))
  end

  it "renders new show form" do
    render

    assert_select "form[action=?][method=?]", shows_path, "post" do

      assert_select "input[name=?]", "show[title]"

      assert_select "input[name=?]", "show[network]"

      assert_select "input[name=?]", "show[episode_id]"
    end
  end
end
