require "test_helper"

class LightekMailControlsTest < ActionDispatch::IntegrationTest
  test "mailbox keys cannot submit abuse feedback or silently discard Cc and Bcc" do
    user = User.create!(first_name: "Mail", last_name: "Control", role: "super_admin", email_address: "control-api-#{SecureRandom.hex(6)}@example.test", password: "Mail-test-2026-password!")
    domain = LightekMail::Domain.create!(user: user, name: "control-api-#{SecureRandom.hex(6)}.test", verified_at: Time.current)
    account = LightekMail::Account.create!(user: user, domain: domain, address: "care@#{domain.name}", display_name: "Control API", enabled: true)
    LightekMail::SendingPolicy.create_or_find_by!(id: 1).update!(sending_enabled: true)
    headers = {"Authorization" => "Bearer #{account.rotate_token!}", "Idempotency-Key" => "control_api_123"}
    post "/api/lightek-mail/messages", params: {to: ["recipient@example.test"], cc: ["copy@example.test"], bcc: ["blind@example.test"], subject: "Hello", text: "Hello"}, headers: headers, as: :json
    assert_response :accepted
    assert_equal 1, account.messages.count
    assert_equal ["copy@example.test"], account.messages.last.cc_addresses
    assert_equal ["blind@example.test"], account.messages.last.bcc_addresses
    assert_equal 3, LightekMail::SendReservation.find_by!(message_id: account.messages.last.id).recipient_count
    id = response.parsed_body.fetch("id")
    old = ENV["LIGHTEK_MAIL_FEEDBACK_TOKEN"]
    ENV["LIGHTEK_MAIL_FEEDBACK_TOKEN"] = "fixture-feedback-#{'a' * 40}"
    payload = {message_id: id, kind: "complaint", event_key: "control_feedback_123"}
    post "/api/lightek-mail/feedback", params: payload, headers: headers, as: :json
    assert_response :unauthorized
    refute account.reload.suspended?
    2.times do
      post "/api/lightek-mail/feedback", params: payload, headers: {"X-Lightek-Mail-Feedback" => ENV["LIGHTEK_MAIL_FEEDBACK_TOKEN"]}, as: :json
      assert_response :accepted
    end
    assert account.reload.suspended?
    assert_equal 1, LightekMail::FeedbackEvent.where(message_id: id).count
  ensure
    old.nil? ? ENV.delete("LIGHTEK_MAIL_FEEDBACK_TOKEN") : ENV["LIGHTEK_MAIL_FEEDBACK_TOKEN"] = old
  end
end
