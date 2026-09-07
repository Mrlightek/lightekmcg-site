require 'rails_helper'

RSpec.describe "system_jobs/show", type: :view do
  before(:each) do
    assign(:system_job, SystemJob.create!(
      name: "Name",
      priority: 2,
      job_item: nil
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Name/)
    expect(rendered).to match(/2/)
    expect(rendered).to match(//)
  end
end
