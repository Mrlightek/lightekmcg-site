require 'rails_helper'

RSpec.describe "system_jobs/new", type: :view do
  before(:each) do
    assign(:system_job, SystemJob.new(
      name: "MyString",
      priority: 1,
      job_item: nil
    ))
  end

  it "renders new system_job form" do
    render

    assert_select "form[action=?][method=?]", system_jobs_path, "post" do

      assert_select "input[name=?]", "system_job[name]"

      assert_select "input[name=?]", "system_job[priority]"

      assert_select "input[name=?]", "system_job[job_item_id]"
    end
  end
end
