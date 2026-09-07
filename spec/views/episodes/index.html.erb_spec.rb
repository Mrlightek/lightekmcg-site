require 'rails_helper'

RSpec.describe "episodes/index", type: :view do
  before(:each) do
    assign(:episodes, [
      Episode.create!(
        title: "Title",
        subtitle: "Subtitle",
        url: "Url",
        description: "MyText",
        show_title: "Show Title",
        show_description: "MyText"
      ),
      Episode.create!(
        title: "Title",
        subtitle: "Subtitle",
        url: "Url",
        description: "MyText",
        show_title: "Show Title",
        show_description: "MyText"
      )
    ])
  end

  it "renders a list of episodes" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Title".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Subtitle".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Url".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("MyText".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Show Title".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("MyText".to_s), count: 2
  end
end
