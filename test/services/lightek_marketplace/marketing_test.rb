require "test_helper"

class LightekMarketplaceMarketingTest < ActiveSupport::TestCase
  test "feature copy becomes structured lines without empty entries" do
    form = LightekMarketplace::ProductForm.new(attributes: {
      marketing_features_text: "Storefront and checkout\n\nDedicated customer VPS\n"
    })
    assert_equal ["Storefront and checkout", "Dedicated customer VPS"], form.marketing_features
  end

  test "faq copy becomes question answer pairs" do
    form = LightekMarketplace::ProductForm.new(attributes: {
      marketing_faq_text: "Can I sell products? | Yes, when storefront is enabled.\n"
    })
    assert_equal [{"question" => "Can I sell products?", "answer" => "Yes, when storefront is enabled."}], form.marketing_faq
  end

  test "invalid faq rows are rejected" do
    form = LightekMarketplace::ProductForm.new(attributes: {marketing_faq_text: "Missing answer"})
    form.valid?
    assert form.errors[:marketing_faq_text].any?
  end
end
