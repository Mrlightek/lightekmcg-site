require "test_helper"
class LightekMarketingEmailDeliveryTest < ActiveSupport::TestCase
  test "draft campaigns cannot send" do
    campaign = LightekMarketing::Campaign.new(channel: "email", status: "draft")
    assert_raises(LightekMarketing::EmailDelivery::Invalid) do
      LightekMarketing::EmailDelivery.call!(campaign: campaign, actor: nil)
    end
  end
end
