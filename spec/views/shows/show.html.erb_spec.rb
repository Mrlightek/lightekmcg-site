require 'rails_helper'

RSpec.describe "shows/show", type: :view do
  before(:each) do
    assign(:show, Show.create!(
      title: "Title",
      network: "Network",
      episode: nil
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Title/)
    expect(rendered).to match(/Network/)
    expect(rendered).to match(//)
  end
end
