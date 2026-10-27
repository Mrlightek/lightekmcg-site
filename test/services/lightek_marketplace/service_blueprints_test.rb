require "test_helper"

class LightekMarketplaceServiceBlueprintsTest < ActiveSupport::TestCase
  test "all supported fulfillment blueprints are registered" do
    assert_equal %w[website application_access compute_instance managed_work],
      LightekMarketplace::ServiceBlueprints.all.map(&:key)
    assert_equal "compute", LightekMarketplace::ServiceBlueprints.find("compute_instance").delivery
    assert_nil LightekMarketplace::ServiceBlueprints.find("arbitrary")
  end

  test "product form chooses correct fulfillment blueprint for delivery method" do
    form = LightekMarketplace::ProductForm.new(attributes: {
      name: "Compute", description: "Managed instance",
      billing: "monthly", monthly_price: "25.00",
      delivery: "compute", blueprint_key: "website"
    })
    assert_equal "compute_instance", form.blueprint_key
    assert_equal "compute", form.delivery
  end

  test "compute delivery requires a recurring subscription" do
    form = LightekMarketplace::ProductForm.new(attributes: {
      name: "Compute", description: "Managed instance",
      billing: "once", price: "25.00", delivery: "compute"
    })
    refute form.valid?
    assert_includes form.errors[:delivery], "requires a monthly or annual subscription"
  end
end
