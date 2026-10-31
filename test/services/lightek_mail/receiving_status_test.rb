require "test_helper"
require "resolv"

class LightekMailReceivingStatusTest < ActiveSupport::TestCase
  test "disabled and unverified mailboxes fail before any DNS request" do
    account = LightekMail::Account.new(enabled: false)
    Resolv::DNS.stub(:open, ->(*) { flunk "DNS should not be queried" }) do
      refute LightekMail::ReceivingStatus.check(account).fetch(:ok)
      account.enabled = true
      account.domain = LightekMail::Domain.new(name: "client.test")
      refute LightekMail::ReceivingStatus.check(account).fetch(:ok)
    end
  end

  test "MX mismatch identifies the actual incoming provider and matching MX does not claim delivery" do
    account = LightekMail::Account.new(enabled: true, domain: LightekMail::Domain.new(name: "client.test", verified_at: Time.current))
    resolver = Minitest::Mock.new
    resolver.expect(:timeouts=, nil, [2])
    resolver.expect(:getresources, [Resolv::DNS::Resource::IN::MX.new(10, Resolv::DNS::Name.create("other.test."))], ["client.test.", Resolv::DNS::Resource::IN::MX])
    Resolv::DNS.stub(:open, ->(&block) { block.call(resolver) }) do
      result = LightekMail::ReceivingStatus.check(account)
      refute result.fetch(:ok)
      assert_includes result.fetch(:message), "other.test"
    end
    resolver.verify
    resolver = Minitest::Mock.new
    resolver.expect(:timeouts=, nil, [2])
    resolver.expect(:getresources, [Resolv::DNS::Resource::IN::MX.new(10, Resolv::DNS::Name.create("mail.lightekmcg.com."))], ["client.test.", Resolv::DNS::Resource::IN::MX])
    old = ENV.delete("LIGHTEK_MAIL_HOST")
    Resolv::DNS.stub(:open, ->(&block) { block.call(resolver) }) do
      result = LightekMail::ReceivingStatus.check(account)
      assert result.fetch(:ok)
      assert_includes result.fetch(:message), "does not test SMTP delivery"
    end
    resolver.verify
  ensure
    ENV["LIGHTEK_MAIL_HOST"] = old if old
  end
end
