require 'rails_helper'

RSpec.describe "nevaehs/edit", type: :view do
  let(:nevaeh) {
    Nevaeh.create!()
  }

  before(:each) do
    assign(:nevaeh, nevaeh)
  end

  it "renders the edit nevaeh form" do
    render

    assert_select "form[action=?][method=?]", nevaeh_path(nevaeh), "post" do
    end
  end
end
