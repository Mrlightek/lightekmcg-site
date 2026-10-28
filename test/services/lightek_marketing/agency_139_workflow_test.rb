require "test_helper"

class Agency139WorkflowTest < ActiveSupport::TestCase
  test "marketing contact is not subscribed by default" do
    contact = LightekMarketing::Contact.new(email: "buyer@example.com")
    assert_not contact.subscribed_at?
  end

  test "unsupported social providers are rejected" do
    connection = LightekMarketing::SocialConnection.new(provider: "unconfigured", account_label: "Main", publish_endpoint: "https://example.com", credential_key: "env")
    assert_not connection.valid?
  end
end
