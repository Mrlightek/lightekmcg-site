require 'rails_helper'

RSpec.describe "departments/index", type: :view do
  before(:each) do
    assign(:departments, [
      Department.create!(
        title: "Title",
        system_job: nil
      ),
      Department.create!(
        title: "Title",
        system_job: nil
      )
    ])
  end

  it "renders a list of departments" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Title".to_s), count: 2
    assert_select cell_selector, text: Regexp.new(nil.to_s), count: 2
  end
end
