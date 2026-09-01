require 'rails_helper'

RSpec.describe "nevaehs/index", type: :view do
  before(:each) do
    assign(:nevaehs, [
      Nevaeh.create!(),
      Nevaeh.create!()
    ])
  end

  it "renders a list of nevaehs" do
    render
    cell_selector = 'div>p'
  end
end
