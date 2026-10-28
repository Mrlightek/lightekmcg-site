require "test_helper"
class SocialPublicationOperationsTest < ActiveSupport::TestCase
  test "refresh refuses non TikTok posts" do
    post = Struct.new(:connection).new(Struct.new(:provider).new("facebook"))
    assert_raises(LightekMarketing::SocialPublicationOperations::Invalid) do
      LightekMarketing::SocialPublicationOperations.refresh!(post: post)
    end
  end
end
