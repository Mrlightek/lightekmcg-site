require "test_helper"

class LightekDeploymentProfileCatalogTest < ActiveSupport::TestCase
  test "all five PLP profiles are safe and contain first-run defaults" do
    %w[business social media creator enterprise].each do |name|
      profile = Lightek::Deployments::ProfileCatalog.fetch(name)
      assert_equal name, profile["profile"]
      assert_equal "customer_isolated", profile["mode"]
      assert_equal false, profile.dig("security", "inherit_corporate_knowledge")
      assert_equal false, profile.dig("security", "inherit_platform_secrets")
      assert profile.dig("defaults", "pages").any? { |p| p["slug"] == "home" }
    end
  end

  test "unknown names cannot select paths" do
    assert_raises(ArgumentError) { Lightek::Deployments::ProfileCatalog.fetch("../../secrets") }
  end

  test "insecure configuration is rejected" do
    data = Lightek::Deployments::ProfileCatalog.fetch("business")
    data["security"]["inherit_platform_secrets"] = true
    assert_raises(ArgumentError) { Lightek::Deployments::ProfileCatalog.validate!(data, "business") }
  end
end
