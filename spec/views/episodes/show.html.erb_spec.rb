require 'rails_helper'

RSpec.describe "episodes/show", type: :view do
  before(:each) do
    assign(:episode, Episode.create!(
      title: "Title",
      subtitle: "Subtitle",
      url: "Url",
      description: "MyText",
      show_title: "Show Title",
      show_description: "MyText"
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Title/)
    expect(rendered).to match(/Subtitle/)
    expect(rendered).to match(/Url/)
    expect(rendered).to match(/MyText/)
    expect(rendered).to match(/Show Title/)
    expect(rendered).to match(/MyText/)
  end
end
