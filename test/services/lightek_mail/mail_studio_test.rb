require "test_helper"
require "socket"
class LightekMailStudioTest < ActiveSupport::TestCase
  setup { LightekMail::SendingPolicy.create_or_find_by!(id: 1).update!(sending_enabled: true) }
  def actor(role = "super_admin")
    User.create!(first_name: "Mail", last_name: "Operator", role: role, email_address: "entitled-#{SecureRandom.hex(5)}@example.test", password: "Mail-test-2026-password!")
  end
  def mailbox(user = actor)
    domain = LightekMail::Domain.create!(user: user, name: "client-#{SecureRandom.hex(5)}.test", verified_at: Time.current)
    LightekMail::Account.create!(user: user, domain: domain, address: "hello@#{domain.name}", display_name: "Client team", enabled: true)
  end
  def message_attributes = {to: "recipient@example.test", subject: "Hello", text: "A real plain-text message"}
  def with_mail_stub(object, method, callable)
    original = object.method(method)
    object.define_singleton_method(method, callable)
    yield
  ensure
    object.define_singleton_method(method, original) if original
  end
  test "email builder escapes values strips executable content and preserves text" do
    result = LightekMail::TemplateRenderer.render({heading: "Hello {{name}}", body: "Message {{subject}}", button_label: "Visit", button_url: "https://example.test/", footer: "Our team"}, {"name"=>"<script>alert(1)</script>", "subject"=>"A & B"})
    assert_includes result[:html], "&lt;script&gt;"
    refute_includes result[:html], "<script>"
    assert_includes result[:text], "A & B"
    assert_includes result[:html], "https://example.test/"
    custom = LightekMail::TemplateRenderer.render({html: '<script>alert(1)</script><img src="https://tracker.test"><a href="javascript:alert(1)">Hello</a>', text: "Custom text"})
    refute_includes custom[:html], "<script"
    refute_includes custom[:html], "<img"
    refute_includes custom[:html], "javascript:"
    assert_equal "Custom text", custom[:text]
    assert_raises(ArgumentError) { LightekMail::TemplateRenderer.render({button_url:"javascript:evil"}) }
    assert_raises(ArgumentError) { LightekMail::TemplateRenderer.render({body:"{{unknown}}"}) }
  end
  test "mailbox ownership and tokens isolate accounts and rotation revokes old credentials" do
    first, second = mailbox(actor("client")), mailbox(actor("client"))
    assert_equal [first.id], LightekMail::Access.accounts(first.user).pluck(:id)
    assert_raises(ActiveRecord::RecordNotFound) { LightekMail::Access.accounts(first.user).find(second.id) }
    token = first.rotate_token!
    assert_equal first, LightekMail::Account.authenticate(token)
    refute_equal token, first.reload.token_digest
    first.rotate_token!
    assert_nil LightekMail::Account.authenticate(token)
    assert_nil LightekMail::Account.authenticate("invalid")
  end
  test "HTTP retry idempotency quota and sender checks prevent duplicate or cross-domain sends" do
    account = mailbox
    first = LightekMail::Submission.create!(account: account, attributes: message_attributes, idempotency_key: "request_123")
    again = LightekMail::Submission.create!(account: account, attributes: message_attributes, idempotency_key: "request_123")
    assert_equal first.id, again.id
    assert_equal 1, account.messages.count
    assert_raises(ArgumentError) { LightekMail::Submission.create!(account: account, attributes: message_attributes.merge(from:"forged@another.test")) }
    account.update!(daily_limit: 1)
    first.destroy! # Deleting history must not replenish the daily sending allowance.
    assert_raises(LightekMail::Submission::Unavailable) { LightekMail::Submission.create!(account: account, attributes: message_attributes) }
    account.update!(enabled: false)
    draft = LightekMail::Submission.create!(account: account, attributes: message_attributes, draft: true)
    assert_equal "draft", draft.state
    assert_raises(LightekMail::Submission::Unavailable) { LightekMail::Submission.send_draft!(account, draft) }
  end
  test "a mailbox cannot use another mailbox template" do
    account, other = mailbox, mailbox
    template = other.templates.create!(name:"Other", subject:"Other", document:{body:"Private"})
    assert_raises(ActiveRecord::RecordNotFound) { LightekMail::Submission.create!(account:account, attributes:message_attributes.merge(template_id:template.id)) }
    account.auto_template = template
    refute account.valid?
  end
  test "SMTP sends real multipart content once and labels acceptance without delivery claims" do
    account = mailbox
    template = account.templates.create!(name:"Welcome", subject:"Hi {{name}}", document:{heading:"Welcome {{name}}",body:"Your account is ready",footer:"Client team"})
    message = LightekMail::Submission.create!(account:account,attributes:message_attributes.merge(template_id:template.id,variables:{name:"Tiff"}))
    server = TCPServer.new("127.0.0.1",0)
    settings = {address:"127.0.0.1",port:server.addr[1],domain:"mail.example.test",enable_starttls_auto:false,open_timeout:2,read_timeout:2}
    wire = Queue.new
    receiver = Thread.new do
      client = server.accept
      client.write("220 fixture ESMTP\r\n")
      payload = +""
      while line = client.gets
        if line.start_with?("EHLO", "HELO") then client.write("250 fixture\r\n")
        elsif line.start_with?("MAIL", "RCPT", "RSET") then client.write("250 OK\r\n")
        elsif line.start_with?("DATA")
          client.write("354 Go\r\n")
          while (body = client.gets) && body != ".\r\n"; payload << body; end
          wire << payload
          client.write("250 queued\r\n")
        elsif line.start_with?("QUIT") then client.write("221 Bye\r\n");break
        else client.write("250 OK\r\n")
        end
      end
      client.close
    end
    with_mail_stub(LightekMail::SpamScanner,:check!,->(*) { true }) do
      with_mail_stub(LightekMail::Transport,:settings,-> {settings}) { LightekMail::DeliverJob.perform_now(message.id) }
    end
    receiver.join(4)
    assert_equal "sent", message.reload.state
    assert message.submitted_at
    parsed = Mail.read_from_string(wire.pop)
    assert_equal [account.address], parsed.from
    assert_equal "Hi Tiff", parsed.subject
    assert_includes parsed.text_part.decoded, "Welcome Tiff"
    assert_includes parsed.html_part.decoded, "<table"
    with_mail_stub(LightekMail::MessageMailer,:outbound,->(*) { raise "must not send twice" }) { LightekMail::DeliverJob.perform_now(message.id) }
    assert_equal "sent", message.reload.state
  ensure
    server&.close
    receiver&.kill if receiver&.alive?
  end
  test "ambiguous SMTP failure is not automatically retried" do
    message = LightekMail::Submission.create!(account:mailbox,attributes:message_attributes)
    delivery = Object.new
    delivery.define_singleton_method(:message) { Mail.new }
    delivery.define_singleton_method(:deliver_now) { raise IOError, "fixture failure" }
    with_mail_stub(LightekMail::SpamScanner,:check!,->(*) { true }) do
      with_mail_stub(LightekMail::MessageMailer,:outbound,->(*) { delivery }) { LightekMail::DeliverJob.perform_now(message.id) }
    end
    assert_equal "uncertain", message.reload.state
    refute_includes message.error_message, "fixture failure"
    with_mail_stub(LightekMail::MessageMailer,:outbound,->(*) {raise "duplicate send"}) { LightekMail::DeliverJob.perform_now(message.id) }
    assert_equal "uncertain", message.reload.state
  end
  test "inbound envelope controls delivery preserves attachments and deduplicates retries" do
    account, forged = mailbox, mailbox
    mail = Mail.new do
      from "sender@example.test"
      to forged.address
      subject "An attachment"
      text_part {body "Hello from outside"}
      html_part {body '<p>Hello</p><img src="https://tracker.test">'}
      add_file filename:"note.txt",content:"Attached content"
    end
    inbound = LightekMail::Inbound.accept!(raw:mail.encoded,recipients:[account.address])
    inbound.route
    inbound.route
    assert_equal 1, account.messages.count
    assert_equal 0, forged.messages.count
    record = account.messages.first
    assert_equal "Attached content", record.attachments.first.download
    assert record.source.attached?
    assert_includes record.text_body, "Hello from outside"
    refute_includes record.html_body, "tracker.test"
    assert_equal inbound.id, LightekMail::Inbound.accept!(raw:mail.encoded,recipients:[account.address]).id
  end
  test "auto replies are rate limited and skip automated list and bounce mail" do
    account = mailbox
    template = account.templates.create!(name:"Away",subject:"Away",document:{body:"Thanks {{name}}"})
    account.update!(auto_template:template,auto_reply_enabled:true)
    inbound = account.messages.create!(direction:"inbound",state:"inbox",from_address:"sender@example.test",to_addresses:[account.address],subject:"Hi",message_id:"fixture@example.test")
    mail = Mail.new(from:"sender@example.test",to:account.address,subject:"Hi",body:"Hello")
    mail.return_path="sender@example.test"
    2.times { LightekMail::AutoResponder.call(account,inbound,mail) }
    assert_equal 1, account.messages.where(direction:"outbound").count
    reply = LightekMail::MessageMailer.outbound(account.messages.where(direction:"outbound").first,auto_reply:true).message
    assert_equal "auto-replied",reply["Auto-Submitted"].value
    assert_equal "All",reply["X-Auto-Response-Suppress"].value
    assert_equal account.address,Mail::SmtpEnvelope.new(reply).from
    %w[Auto-Submitted List-Id Precedence].each_with_index do |header,index|
      altered=Mail.new(from:"sender#{index}@example.test",to:account.address,body:"Hello")
      altered.return_path="sender#{index}@example.test"
      altered[header]=header=="Precedence" ? "bulk" : "auto-replied"
      LightekMail::AutoResponder.call(account,inbound,altered)
    end
    assert_equal 1, account.messages.where(direction:"outbound").count
  end
  test "inbound acceptance persists HTML-only mail and fails before acknowledging a full mailbox" do
    account = mailbox
    mail = Mail.new(from:"sender@example.test",to:account.address,subject:"HTML only",content_type:"text/html; charset=UTF-8",body:"<p>Already in your inbox</p>")
    LightekMail::Inbound.accept!(raw:mail.encoded,recipients:[account.address])
    assert_equal 1,account.messages.count
    assert_includes account.messages.first.text_body,"Already in your inbox"
    assert_includes account.messages.first.html_body,"<p>"
    account.update!(storage_limit:1)
    mail.subject="Second message"
    before = ActionMailbox::InboundEmail.count
    assert_raises(LightekMail::Submission::Unavailable) { LightekMail::Inbound.accept!(raw:mail.encoded,recipients:[account.address]) }
    assert_equal before,ActionMailbox::InboundEmail.count
    assert_equal 1,account.messages.count
  end

end
