require "test_helper"

class LightekMarketingTiktokVideoUploadTest < ActiveSupport::TestCase
  test "rejects hosts that have not been verified" do
    assert_not LightekMarketing::TiktokVideoUpload.verified_host?("unverified.example")
  end
end
