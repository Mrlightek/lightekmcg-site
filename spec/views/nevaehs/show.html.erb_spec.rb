require 'rails_helper'

RSpec.describe "nevaehs/show", type: :view do
  before(:each) do
    assign(:nevaeh, Nevaeh.create!())
  end

  it "renders attributes in <p>" do
    render
  end
end
