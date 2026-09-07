require 'rails_helper'

RSpec.describe "departments/new", type: :view do
  before(:each) do
    assign(:department, Department.new(
      title: "MyString",
      system_job: nil
    ))
  end

  it "renders new department form" do
    render

    assert_select "form[action=?][method=?]", departments_path, "post" do

      assert_select "input[name=?]", "department[title]"

      assert_select "input[name=?]", "department[system_job_id]"
    end
  end
end
