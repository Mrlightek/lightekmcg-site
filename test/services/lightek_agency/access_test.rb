require "test_helper"

class LightekAgencyAccessTest < ActiveSupport::TestCase
  test "anonymous visitors cannot gain agency site access" do
    assert_empty LightekAgency::Access.sites_for(nil)
  end

  test "unsubscribed contacts are excluded from audiences" do
    scope = LightekMarketing::Contact.subscribed
    assert scope.where(subscribed_at: nil).none?
  end
end
