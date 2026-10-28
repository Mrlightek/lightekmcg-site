require "test_helper"

class LightekMarketplaceDeploymentPolicyTest < ActiveSupport::TestCase
  test "paid managed purchases are assigned dedicated VPS" do
    offer = Struct.new(:mode, :meta).new("paid", {"lightek_marketplace" => {"version" => 89}})
    purchase = Struct.new(:status, :offer).new("paid", offer)
    assert_equal "dedicated_vps", LightekMarketplace::DeploymentPolicy.target_for(purchase)
  end

  test "free shared deployment requires explicit setting" do
    offer = Struct.new(:mode, :meta).new("free", {"lightek_marketplace" => {"version" => 89, "deployment_target" => "shared"}})
    purchase = Struct.new(:status, :offer).new("paid", offer)
    assert_equal "shared", LightekMarketplace::DeploymentPolicy.target_for(purchase)
  end

  test "unsettled purchases are not eligible for deployment" do
    offer = Struct.new(:mode, :meta).new("paid", {"lightek_marketplace" => {"version" => 89}})
    purchase = Struct.new(:status, :offer).new("pending", offer)
    assert_raises(LightekMarketplace::DeploymentPolicy::NotEligible) do
      LightekMarketplace::DeploymentPolicy.target_for(purchase)
    end
  end
end
