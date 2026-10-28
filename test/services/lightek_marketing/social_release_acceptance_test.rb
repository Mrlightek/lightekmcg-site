require "test_helper"

class SocialReleaseAcceptanceTest < ActiveSupport::TestCase
  FakeConnection = Struct.new(:enabled?, :provider)
  FakeCampaign = Struct.new(:status)
  FakePost = Struct.new(:status, :remote_id, :connection, :campaign, :error, :submission_status) do
    def with_lock
      yield
    end
    def update!(attributes)
      attributes.each { |key, value| public_send("#{key}=", value) }
    end
  end

  test "unknown provider outcome cannot be published a second time" do
    post = FakePost.new("needs_review", nil, FakeConnection.new(true, "facebook"), FakeCampaign.new("ready"))
    assert_raises(LightekMarketing::SocialDispatch::Unavailable) do
      LightekMarketing::SocialDispatch.call!(post: post)
    end
  end

  test "existing provider ID prevents duplicate submission" do
    post = FakePost.new("pending", "remote-123", FakeConnection.new(true, "facebook"), FakeCampaign.new("ready"))
    assert_raises(LightekMarketing::SocialDispatch::Unavailable) do
      LightekMarketing::SocialDispatch.call!(post: post)
    end
  end

  test "operator retry refuses uncertain provider outcome" do
    post = FakePost.new("needs_review", nil, FakeConnection.new(true, "facebook"), FakeCampaign.new("ready"))
    assert_raises(LightekMarketing::SocialPublicationOperations::Invalid) do
      LightekMarketing::SocialPublicationOperations.retry!(post: post)
    end
  end
end
