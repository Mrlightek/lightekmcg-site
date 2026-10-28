require "test_helper"
class TiktokSubmissionLifecycleTest < ActiveSupport::TestCase
  test "requires TikTok connection before polling" do
    connection = Struct.new(:provider).new("facebook")
    post = Struct.new(:connection, :remote_id) do
      def with_lock = yield
    end.new(connection, "test")
    assert_raises(ArgumentError) { LightekMarketing::TiktokSubmissionLifecycle.refresh!(post: post) }
  end
end
