require "test_helper"

class LightekMarketingSocialProvidersTest < ActiveSupport::TestCase
  test "rejects unconfigured provider" do
    connection = Struct.new(:provider).new("unknown")
    assert_raises(LightekMarketing::SocialProviders::Error) do
      LightekMarketing::SocialProviders.publish!(connection: connection, campaign: nil)
    end
  end

  test "social vault supports the defined providers" do
    assert_equal %w[page_id access_token], LightekMarketing::SocialVault::PROVIDERS.fetch("facebook")
    assert_equal %w[instagram_user_id access_token], LightekMarketing::SocialVault::PROVIDERS.fetch("instagram")
  end
end
