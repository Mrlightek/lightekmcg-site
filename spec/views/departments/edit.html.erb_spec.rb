require 'rails_helper'

RSpec.describe "departments/edit", type: :view do
  let(:department) {
    Department.create!(
      title: "MyString",
      system_job: nil
    )
  }

  before(:each) do
    assign(:department, department)
  end

  it "renders the edit department form" do
    render

    assert_select "form[action=?][method=?]", department_path(department), "post" do

      assert_select "input[name=?]", "department[title]"

      assert_select "input[name=?]", "department[system_job_id]"
    end
  end
end
