require 'rails_helper'

RSpec.describe "channels/index", type: :view do
  before(:each) do
    assign(:channels, [
      Channel.create!(
        name: "Name",
        logo: "Logo",
        show: nil
      ),
      Channel.create!(
        name: "Name",
        logo: "Logo",
        show: nil
      )
    ])
  end

  it "renders a list of channels" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Name".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Logo".to_s), count: 2
    assert_select cell_selector, text: Regexp.new(nil.to_s), count: 2
  end
end
