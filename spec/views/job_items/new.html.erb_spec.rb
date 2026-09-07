require 'rails_helper'

RSpec.describe "job_items/new", type: :view do
  before(:each) do
    assign(:job_item, JobItem.new(
      title: "MyString",
      description: "MyText"
    ))
  end

  it "renders new job_item form" do
    render

    assert_select "form[action=?][method=?]", job_items_path, "post" do

      assert_select "input[name=?]", "job_item[title]"

      assert_select "textarea[name=?]", "job_item[description]"
    end
  end
end
