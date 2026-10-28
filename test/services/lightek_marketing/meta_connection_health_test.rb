require "test_helper"

class MetaConnectionHealthTest < ActiveSupport::TestCase
  test "rejects non Meta providers before reading Vault" do
    connection = Struct.new(:provider, :enabled?).new("tiktok", true)
    assert_raises(LightekMarketing::MetaConnectionHealth::Unavailable) do
      LightekMarketing::MetaConnectionHealth.check!(connection: connection)
    end
  end
end
