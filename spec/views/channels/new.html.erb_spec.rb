require 'rails_helper'

RSpec.describe "channels/new", type: :view do
  before(:each) do
    assign(:channel, Channel.new(
      name: "MyString",
      logo: "MyString",
      show: nil
    ))
  end

  it "renders new channel form" do
    render

    assert_select "form[action=?][method=?]", channels_path, "post" do

      assert_select "input[name=?]", "channel[name]"

      assert_select "input[name=?]", "channel[logo]"

      assert_select "input[name=?]", "channel[show_id]"
    end
  end
end
