require 'rails_helper'

RSpec.describe "shows/edit", type: :view do
  let(:show) {
    Show.create!(
      title: "MyString",
      network: "MyString",
      episode: nil
    )
  }

  before(:each) do
    assign(:show, show)
  end

  it "renders the edit show form" do
    render

    assert_select "form[action=?][method=?]", show_path(show), "post" do

      assert_select "input[name=?]", "show[title]"

      assert_select "input[name=?]", "show[network]"

      assert_select "input[name=?]", "show[episode_id]"
    end
  end
end
