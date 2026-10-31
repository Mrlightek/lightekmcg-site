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

class LightekMailRecipientExportTest < ActionDispatch::IntegrationTest
  test "mail VM route export requires ingress credentials and includes only receiving eligible accounts" do
    user = User.create!(first_name: "Mail", last_name: "Routing", role: "super_admin", email_address: "route-api-#{SecureRandom.hex(6)}@example.test", password: "Mail-test-2026-password!")
    domain = LightekMail::Domain.create!(user: user, name: "route-api-#{SecureRandom.hex(6)}.test", verified_at: Time.current)
    ready = LightekMail::Account.create!(user: user, domain: domain, address: "care@#{domain.name}", display_name: "Ready", enabled: true)
    paused = LightekMail::Account.create!(user: user, domain: domain, address: "paused@#{domain.name}", display_name: "Paused", enabled: false)
    unverified = LightekMail::Domain.create!(user: user, name: "unverified-#{SecureRandom.hex(6)}.test")
    unknown = LightekMail::Account.create!(user: user, domain: unverified, address: "care@#{unverified.name}", display_name: "Unverified", enabled: true)
    old = ENV["LIGHTEK_MAIL_INGRESS_TOKEN"]
    ENV["LIGHTEK_MAIL_INGRESS_TOKEN"] = "fixture-ingress-#{'c' * 40}"
    get "/api/lightek-mail/routes"
    assert_response :unauthorized
    get "/api/lightek-mail/routes", headers: {"Authorization" => "Bearer #{ready.rotate_token!}"}
    assert_response :unauthorized
    get "/api/lightek-mail/routes", headers: {"X-Lightek-Mail-Ingress" => ENV["LIGHTEK_MAIL_INGRESS_TOKEN"]}
    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    recipients = response.parsed_body.fetch("recipients")
    assert_includes recipients, ready.address
    refute_includes recipients, paused.address
    refute_includes recipients, unknown.address
    assert_equal ["recipients"], response.parsed_body.keys
  ensure
    old.nil? ? ENV.delete("LIGHTEK_MAIL_INGRESS_TOKEN") : ENV["LIGHTEK_MAIL_INGRESS_TOKEN"] = old
  end

  test "authenticated raw MIME enters the inbox independently of the global sending pause" do
    user = User.create!(first_name: "Receive", last_name: "Only", role: "super_admin", email_address: "receive-api-#{SecureRandom.hex(6)}@example.test", password: "Mail-test-2026-password!")
    domain = LightekMail::Domain.create!(user: user, name: "receive-api-#{SecureRandom.hex(6)}.test", verified_at: Time.current)
    account = LightekMail::Account.create!(user: user, domain: domain, address: "care@#{domain.name}", display_name: "Receive", enabled: true)
    LightekMail::SendingPolicy.current.update!(sending_enabled: false, stop_reason: "Outbound paused")
    old = ENV["LIGHTEK_MAIL_INGRESS_TOKEN"]
    ENV["LIGHTEK_MAIL_INGRESS_TOKEN"] = "fixture-ingress-#{'d' * 40}"
    mail = Mail.new do
      from "outside@example.test"
      to "different@example.test"
      cc "visible@example.test"
      subject "External receive proof"
      text_part { body "Delivered into webmail" }
      add_file filename: "proof.txt", content: "Proof attachment"
    end
    2.times do
      post "/api/lightek-mail/inbound", params: mail.encoded, headers: {"Content-Type" => "message/rfc822", "X-Lightek-Mail-Ingress" => ENV["LIGHTEK_MAIL_INGRESS_TOKEN"], "X-Lightek-Mail-Recipients" => [account.address].to_json}
      assert_response :accepted
    end
    assert_equal 1, account.messages.count
    record = account.messages.first
    assert_equal "inbox", record.state
    assert_equal ["visible@example.test"], record.cc_addresses
    assert_includes record.text_body, "Delivered into webmail"
    assert_equal "Proof attachment", record.attachments.first.download
    assert record.source.attached?
    refute LightekMail::SendingPolicy.current.sending_enabled?
  ensure
    old.nil? ? ENV.delete("LIGHTEK_MAIL_INGRESS_TOKEN") : ENV["LIGHTEK_MAIL_INGRESS_TOKEN"] = old
  end
  test "authenticated empty installer probe returns 422 without creating mail" do
    old = ENV["LIGHTEK_MAIL_INGRESS_TOKEN"]
    ENV["LIGHTEK_MAIL_INGRESS_TOKEN"] = "fixture-probe-#{'e' * 40}"
    assert_no_difference ["ActionMailbox::InboundEmail.count", "LightekMail::Message.count"] do
      post "/api/lightek-mail/inbound", params: "", headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "X-Lightek-Mail-Ingress" => ENV["LIGHTEK_MAIL_INGRESS_TOKEN"],
        "X-Lightek-Mail-Recipients" => "[]"
      }
      assert_response :unprocessable_entity
    end
  ensure
    old.nil? ? ENV.delete("LIGHTEK_MAIL_INGRESS_TOKEN") : ENV["LIGHTEK_MAIL_INGRESS_TOKEN"] = old
  end

end
