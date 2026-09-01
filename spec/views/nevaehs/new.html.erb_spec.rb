require 'rails_helper'

RSpec.describe "nevaehs/new", type: :view do
  before(:each) do
    assign(:nevaeh, Nevaeh.new())
  end

  it "renders new nevaeh form" do
    render

    assert_select "form[action=?][method=?]", nevaehs_path, "post" do
    end
  end
end
