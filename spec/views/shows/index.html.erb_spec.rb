require 'rails_helper'

RSpec.describe "shows/index", type: :view do
  before(:each) do
    assign(:shows, [
      Show.create!(
        title: "Title",
        network: "Network",
        episode: nil
      ),
      Show.create!(
        title: "Title",
        network: "Network",
        episode: nil
      )
    ])
  end

  it "renders a list of shows" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Title".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Network".to_s), count: 2
    assert_select cell_selector, text: Regexp.new(nil.to_s), count: 2
  end
end
