require 'rails_helper'

RSpec.describe "system_jobs/edit", type: :view do
  let(:system_job) {
    SystemJob.create!(
      name: "MyString",
      priority: 1,
      job_item: nil
    )
  }

  before(:each) do
    assign(:system_job, system_job)
  end

  it "renders the edit system_job form" do
    render

    assert_select "form[action=?][method=?]", system_job_path(system_job), "post" do

      assert_select "input[name=?]", "system_job[name]"

      assert_select "input[name=?]", "system_job[priority]"

      assert_select "input[name=?]", "system_job[job_item_id]"
    end
  end
end
