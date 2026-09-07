require 'rails_helper'

RSpec.describe "departments/show", type: :view do
  before(:each) do
    assign(:department, Department.create!(
      title: "Title",
      system_job: nil
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Title/)
    expect(rendered).to match(//)
  end
end
