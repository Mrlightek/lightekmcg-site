require "test_helper"
require "minitest/mock"
require "net/http"

class LightekMailSpamScannerTest < ActiveSupport::TestCase
  def scan(result)
    response = Struct.new(:code, :body).new("200", result.is_a?(String) ? result : JSON.generate(result))
    session = Object.new
    session.define_singleton_method(:request) { |_request| response }
    mail = Mail.new(from: "sender@example.test", to: "recipient@example.test", subject: "Update", body: "Hello")
    Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(session) }) { LightekMail::SpamScanner.check!(mail) }
  end

  test "valid clean scan passes while spam and malformed results fail closed" do
    assert scan({"action" => "no action", "score" => 0.5})
    assert_raises(LightekMail::SpamScanner::Rejected) { scan({"action" => "reject", "score" => 12}) }
    assert_raises(LightekMail::SpamScanner::Rejected) { scan({"action" => "no action", "score" => 6}) }
    assert_raises(LightekMail::SpamScanner::Unavailable) { scan("not-json") }
    assert_raises(LightekMail::SpamScanner::Unavailable) { scan({"action" => "no action"}) }
    assert_raises(LightekMail::SpamScanner::Unavailable) { scan({"action" => "unknown", "score" => 0}) }
  end

  test "temporary deferrals are not treated as abuse" do
    assert_raises(LightekMail::SpamScanner::Unavailable) { scan({"action" => "soft reject", "score" => 0}) }
    assert_raises(LightekMail::SpamScanner::Unavailable) { scan({"action" => "greylist", "score" => 4}) }
  end

  test "scanner endpoint cannot target external hosts or forward credentials" do
    old = ENV["LIGHTEK_MAIL_RSPAMD_URL"]
    ENV["LIGHTEK_MAIL_RSPAMD_URL"] = "http://external.example.test/checkv2"
    assert_raises(LightekMail::SpamScanner::Unavailable) { scan({"action" => "no action", "score" => 0}) }
  ensure
    old.nil? ? ENV.delete("LIGHTEK_MAIL_RSPAMD_URL") : ENV["LIGHTEK_MAIL_RSPAMD_URL"] = old
  end
end
