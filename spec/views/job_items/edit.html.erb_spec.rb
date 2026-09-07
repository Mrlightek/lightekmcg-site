require 'rails_helper'

RSpec.describe "job_items/edit", type: :view do
  let(:job_item) {
    JobItem.create!(
      title: "MyString",
      description: "MyText"
    )
  }

  before(:each) do
    assign(:job_item, job_item)
  end

  it "renders the edit job_item form" do
    render

    assert_select "form[action=?][method=?]", job_item_path(job_item), "post" do

      assert_select "input[name=?]", "job_item[title]"

      assert_select "textarea[name=?]", "job_item[description]"
    end
  end
end
