require 'rails_helper'

RSpec.describe "channels/show", type: :view do
  before(:each) do
    assign(:channel, Channel.create!(
      name: "Name",
      logo: "Logo",
      show: nil
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Name/)
    expect(rendered).to match(/Logo/)
    expect(rendered).to match(//)
  end
end
