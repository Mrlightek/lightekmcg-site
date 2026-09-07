require 'rails_helper'

RSpec.describe "system_jobs/index", type: :view do
  before(:each) do
    assign(:system_jobs, [
      SystemJob.create!(
        name: "Name",
        priority: 2,
        job_item: nil
      ),
      SystemJob.create!(
        name: "Name",
        priority: 2,
        job_item: nil
      )
    ])
  end

  it "renders a list of system_jobs" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Name".to_s), count: 2
    assert_select cell_selector, text: Regexp.new(2.to_s), count: 2
    assert_select cell_selector, text: Regexp.new(nil.to_s), count: 2
  end
end
