require 'rails_helper'

RSpec.describe "channels/edit", type: :view do
  let(:channel) {
    Channel.create!(
      name: "MyString",
      logo: "MyString",
      show: nil
    )
  }

  before(:each) do
    assign(:channel, channel)
  end

  it "renders the edit channel form" do
    render

    assert_select "form[action=?][method=?]", channel_path(channel), "post" do

      assert_select "input[name=?]", "channel[name]"

      assert_select "input[name=?]", "channel[logo]"

      assert_select "input[name=?]", "channel[show_id]"
    end
  end
end
