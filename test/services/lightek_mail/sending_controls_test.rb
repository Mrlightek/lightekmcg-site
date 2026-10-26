require "test_helper"
require "minitest/mock"

class LightekMailSendingControlsTest < ActiveSupport::TestCase
  setup { LightekMail::SendingPolicy.create_or_find_by!(id: 1).update!(sending_enabled: true) }

  def mailbox(user = nil)
    user ||= User.create!(first_name: "Mail", last_name: "Controls", role: "super_admin", email_address: "control-#{SecureRandom.hex(6)}@example.test", password: "Mail-test-2026-password!")
    domain = LightekMail::Domain.create!(user: user, name: "control-#{SecureRandom.hex(6)}.test", verified_at: Time.current)
    LightekMail::Account.create!(user: user, domain: domain, address: "care@#{domain.name}", display_name: "Controls", enabled: true)
  end

  def send_message(account, recipients: ["recipient@example.test"], key: nil)
    LightekMail::Submission.create!(account: account, attributes: {to: recipients, subject: "A message", text: "Your requested update"}, idempotency_key: key)
  end

  def with_env(values)
    old = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value.to_s }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "recipient reservations survive deletion retries and rolling window boundaries" do
    account = mailbox
    account.update!(minute_limit: 2)
    original = send_message(account, recipients: %w[a@example.test b@example.test], key: "stable_request_123")
    assert_equal original.id, send_message(account, recipients: %w[a@example.test b@example.test], key: "stable_request_123").id
    assert_equal 2, LightekMail::SendReservation.where(account_id: account.id).sum(:recipient_count)
    original.destroy!
    assert_raises(LightekMail::Submission::Unavailable) { send_message(account) }
    travel 61.seconds do
      assert_equal "queued", send_message(account).state
    end
  end

  test "hourly and daily windows cannot be bypassed by waiting out the burst window" do
    account = mailbox
    account.update!(hour_limit: 2, daily_limit: 3)
    send_message(account, recipients: %w[a@example.test b@example.test])
    travel 61.seconds do
      assert_raises(LightekMail::Submission::Unavailable) { send_message(account) }
    end
    travel 3601.seconds do
      send_message(account)
      assert_raises(LightekMail::Submission::Unavailable) { send_message(account) }
    end
    travel 1.day + 1.second do
      assert_equal "queued", send_message(account).state
    end
  end

  test "customer and server limits aggregate across mailboxes and customers" do
    first = mailbox
    sibling = mailbox(first.user)
    other = mailbox
    with_env("LIGHTEK_MAIL_CUSTOMER_MINUTE_LIMIT" => 2, "LIGHTEK_MAIL_SERVER_MINUTE_LIMIT" => 3) do
      send_message(first, recipients: %w[a@example.test b@example.test])
      assert_raises(LightekMail::Submission::Unavailable) { send_message(sibling) }
      send_message(other)
      assert_raises(LightekMail::Submission::Unavailable) { send_message(mailbox) }
    end
    assert_equal 3, LightekMail::SendReservation.sum(:recipient_count)
  end

  test "server stop blocks submissions draft sends and queued SMTP attempts" do
    account = mailbox
    queued = send_message(account)
    draft = LightekMail::Submission.create!(account: account, attributes: {to: "a@example.test", subject: "Draft", text: "Hello"}, draft: true)
    LightekMail::SendingPolicy.find(1).update!(sending_enabled: false)
    assert_raises(LightekMail::Submission::Unavailable) { send_message(account) }
    assert_raises(LightekMail::Submission::Unavailable) { LightekMail::Submission.send_draft!(account, draft) }
    LightekMail::MessageMailer.stub(:outbound, ->(*) { flunk "Paused queue must not reach SMTP" }) do
      LightekMail::DeliverJob.perform_now(queued.id)
    end
    assert_equal "queued", queued.reload.state
    assert_equal "draft", draft.reload.state
    LightekMail::SendingPolicy.delete_all
    assert_raises(LightekMail::Submission::Unavailable) { send_message(account) }
    refute LightekMail::SendingPolicy.find(1).sending_enabled?
  end

  test "Cc Bcc and attachments are supported with full recipient accounting" do
    account = mailbox
    message = LightekMail::Submission.create!(account: account, attributes: {
      to: ["to@example.test"], cc: ["copy@example.test"], bcc: ["blind@example.test"],
      subject: "Update", text: "Hello",
      attachments: [{"filename" => "note.txt", "content_type" => "text/plain", "data" => Base64.strict_encode64("Attached")}]
    })
    assert_equal ["copy@example.test"], message.cc_addresses
    assert_equal ["blind@example.test"], message.bcc_addresses
    assert_equal 3, LightekMail::SendReservation.find_by!(message_id: message.id).recipient_count
    assert_equal "Attached", message.attachments.first.download
    rendered = LightekMail::MessageMailer.outbound(message).message
    assert_equal ["copy@example.test"], rendered.cc
    assert_equal ["blind@example.test"], rendered.bcc
    mail = Mail.new(from: account.address, to: "to@example.test", cc: "copy@example.test", bcc: "blind@example.test", subject: "Update", body: "Hello")
    mail.attachments["note.txt"] = "Attached"
    requests = []
    session = Object.new
    session.define_singleton_method(:request) do |request|
      requests << request
      Struct.new(:code, :body).new("202", '{"id":123,"status":"queued"}')
    end
    Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(session) }) do
      LightekMail::HttpsDelivery.new(token: "fixture-only").deliver!(mail)
    end
    body = JSON.parse(requests.first.body)
    assert_equal ["copy@example.test"], body.fetch("cc")
    assert_equal ["blind@example.test"], body.fetch("bcc")
    assert_equal "Attached", Base64.strict_decode64(body.fetch("attachments").first.fetch("data"))
    mail.smtp_envelope_to = ["elsewhere@example.test"]
    assert_raises(ArgumentError) { LightekMail::HttpsDelivery.new(token: "fixture-only").deliver!(mail) }
  end

  test "scanner outages and rejected spam never reach SMTP and spam suspends new sibling accounts" do
    account = mailbox
    outage = send_message(account)
    spam = send_message(account)
    LightekMail::MessageMailer.stub(:outbound, ->(*) { Struct.new(:message).new(Mail.new(from: account.address, to: "a@example.test", body: "Hello")) }) do
      LightekMail::SpamScanner.stub(:check!, ->(*) { raise LightekMail::SpamScanner::Unavailable }) { LightekMail::DeliverJob.perform_now(outage.id) }
      LightekMail::SpamScanner.stub(:check!, ->(*) { raise LightekMail::SpamScanner::Rejected }) { LightekMail::DeliverJob.perform_now(spam.id) }
    end
    assert_equal "queued", outage.reload.state
    assert_equal "failed", spam.reload.state
    assert account.reload.suspended?
    new_mailbox = mailbox(account.user)
    refute new_mailbox.sending_ready?
    assert_raises(LightekMail::Submission::Unavailable) { send_message(new_mailbox) }
  end

  test "trusted complaint feedback is deduplicated and trips the global stop" do
    messages = 3.times.map { send_message(mailbox) }
    messages.each_with_index do |message, index|
      2.times { LightekMail::Feedback.record!(message_id: message.id, kind: "complaint", event_key: "complaint_#{index}") }
      assert message.account.reload.suspended?
    end
    assert_equal 3, LightekMail::FeedbackEvent.count
    refute LightekMail::SendingPolicy.find(1).sending_enabled?
  end

  test "repeated bounce notifications for one message do not manufacture a bounce outbreak" do
    account = mailbox
    account.update!(minute_limit: 100)
    with_env("LIGHTEK_MAIL_CUSTOMER_MINUTE_LIMIT" => 100, "LIGHTEK_MAIL_SERVER_MINUTE_LIMIT" => 100) do
      messages = 20.times.map { send_message(account) }
      5.times { |index| LightekMail::Feedback.record!(message_id: messages.first.id, kind: "hard_bounce", event_key: "same_bounce_#{index}") }
      refute account.reload.suspended?
      messages.drop(1).first(4).each_with_index { |message, index| LightekMail::Feedback.record!(message_id: message.id, kind: "hard_bounce", event_key: "other_bounce_#{index}") }
      assert account.reload.suspended?
    end
  end

  test "resuming an old queue still enforces SMTP dispatch burst limits" do
    account = mailbox
    account.update!(minute_limit: 1)
    freeze_time do
      first = send_message(account)
      travel 61.seconds
      second = send_message(account)
      submitted = []
      delivery = Struct.new(:message).new(Mail.new(from: account.address, to: "a@example.test", body: "Hello"))
      delivery.define_singleton_method(:deliver_now) { submitted << true }
      LightekMail::MessageMailer.stub(:outbound, ->(*) { delivery }) do
        LightekMail::SpamScanner.stub(:check!, ->(*) { true }) do
          LightekMail::DeliverJob.perform_now(first.id)
          LightekMail::DeliverJob.perform_now(second.id)
          assert_equal 1, submitted.size
          assert_equal "queued", second.reload.state
          assert_nil LightekMail::SendReservation.find_by!(message_id: second.id).dispatched_at
          travel 61.seconds
          LightekMail::DeliverJob.perform_now(second.id)
        end
      end
      assert_equal 2, submitted.size
      assert_equal "sent", second.reload.state
    end
  end

  test "a stop arriving during scanning prevents SMTP" do
    message = send_message(mailbox)
    delivery = Struct.new(:message).new(Mail.new)
    delivery.define_singleton_method(:deliver_now) { raise "SMTP must not be attempted" }
    scanner = ->(*) { LightekMail::SendingPolicy.find(1).update!(sending_enabled: false); true }
    LightekMail::MessageMailer.stub(:outbound, ->(*) { delivery }) do
      LightekMail::SpamScanner.stub(:check!, scanner) { LightekMail::DeliverJob.perform_now(message.id) }
    end
    assert_equal "failed", message.reload.state
    assert_nil LightekMail::SendReservation.find_by!(message_id: message.id).dispatched_at
  end

  test "a normal To-only HTTPS message preserves recipients and stable retries" do
    adapter = LightekMail::HttpsDelivery.new(token: "fixture-only")
    mail = Mail.new(from: "sender@example.test", to: %w[a@example.test b@example.test], subject: "Update", body: "Hello")
    requests = []
    session = Object.new
    session.define_singleton_method(:request) do |request|
      requests << request
      Struct.new(:code, :body).new("202", '{"id":123,"status":"queued"}')
    end
    Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(session) }) { 2.times { adapter.deliver!(mail) } }
    assert_equal %w[a@example.test b@example.test], JSON.parse(requests.first.body).fetch("to")
    assert_equal requests.first["Idempotency-Key"], requests.last["Idempotency-Key"]
  end

  test "an automatic reply rejected by quota cannot leave a partial draft inside inbound intake" do
    account = mailbox
    account.update!(minute_limit: 1)
    send_message(account)
    template = account.templates.create!(name: "Away", subject: "Away", document: {body: "Thanks {{name}}"})
    account.update!(auto_reply_enabled: true, auto_template: template)
    mail = Mail.new(from: "sender@example.test", to: account.address, subject: "Hello", body: "Hello")
    mail.return_path = "sender@example.test"
    LightekMail::Inbound.accept!(raw: mail.encoded, recipients: [account.address])
    assert_equal 1, account.messages.where(direction: "inbound").count
    assert_equal 1, account.messages.where(direction: "outbound").count
    assert_equal 0, account.messages.where(state: "draft").count
  end
end
