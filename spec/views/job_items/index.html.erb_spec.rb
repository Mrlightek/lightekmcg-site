require 'rails_helper'

RSpec.describe "job_items/index", type: :view do
  before(:each) do
    assign(:job_items, [
      JobItem.create!(
        title: "Title",
        description: "MyText"
      ),
      JobItem.create!(
        title: "Title",
        description: "MyText"
      )
    ])
  end

  it "renders a list of job_items" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Title".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("MyText".to_s), count: 2
  end
end
