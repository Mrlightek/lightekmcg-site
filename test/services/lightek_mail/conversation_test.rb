require "test_helper"
require "minitest/mock"

class LightekMailConversationTest < ActiveSupport::TestCase
  def mailbox
    user = User.create!(first_name: "Conversation", last_name: "Mail", role: "super_admin", email_address: "conversation-#{SecureRandom.hex(5)}@example.test", password: "Mail-test-2026-password!")
    domain = LightekMail::Domain.create!(user: user, name: "thread-#{SecureRandom.hex(5)}.test", verified_at: Time.current)
    LightekMail::Account.create!(user: user, domain: domain, address: "hello@#{domain.name}", display_name: "Conversation team", enabled: true)
  end

  def mail_record(account, **attributes)
    account.messages.create!({direction: "inbound", state: "inbox", from_address: "sender@example.test", to_addresses: [account.address], subject: "Launch plan", text_body: "Original message", message_id: "#{SecureRandom.hex(8)}@example.test"}.merge(attributes))
  end

  test "conversation links ancestors and sibling replies without merging unrelated equal subjects" do
    account = mailbox
    root = mail_record(account)
    first = mail_record(account, direction: "outbound", state: "sent", from_address: account.address, in_reply_to: "<#{root.message_id}>")
    second = mail_record(account, in_reply_to: "<#{first.message_id}>")
    sibling = mail_record(account, in_reply_to: root.message_id)
    mail_record(account)
    assert_equal [root.id, first.id, second.id, sibling.id], LightekMail::Conversation.messages(account, second).map(&:id)
  end

  test "identical message IDs across accounts do not expose another mailbox" do
    first, second = mailbox, mailbox
    root = mail_record(first, message_id: "shared@example.test")
    private_message = mail_record(second, message_id: "shared@example.test", text_body: "Private other mailbox")
    reply = mail_record(first, in_reply_to: "<shared@example.test>")
    assert_equal [root.id, reply.id], LightekMail::Conversation.messages(first, reply).map(&:id)
    assert_raises(ActiveRecord::RecordNotFound) { LightekMail::Conversation.messages(first, private_message) }
  end

  test "reply cycles are bounded and trashed history is excluded" do
    account = mailbox
    first = mail_record(account)
    second = mail_record(account, in_reply_to: "<#{first.message_id}>")
    first.update!(in_reply_to: "<#{second.message_id}>")
    assert_equal [first.id, second.id], LightekMail::Conversation.messages(account, second).map(&:id)
    first.update!(trashed: true)
    assert_equal [second.id], LightekMail::Conversation.messages(account, second).map(&:id)
  end

  test "reply keeps the previous message in HTML and text and emits threading headers" do
    account = mailbox
    original = mail_record(account, html_body: '<p style="color:#246644">Previous <strong>message</strong></p>')
    attrs = LightekMail::ComposeMessage.attributes(account: account, original: original, attributes: {to: "sender@example.test", subject: "Re: Launch plan", html: "<p>Our <strong>reply</strong></p>"})
    reply = LightekMail::Submission.create!(account: account, attributes: attrs, draft: true)
    assert_includes reply.text_body, "Our reply"
    assert_includes reply.text_body, "> Original message"
    assert_includes reply.html_body, "Previous <strong>message</strong>"
    assert_includes reply.html_body, "font-family"
    mail = LightekMail::MessageMailer.outbound(reply).message
    assert_equal account.display_name, mail[:from].display_names.first
    assert_equal [account.address], mail.from
    assert_equal original.message_id, mail.in_reply_to
    assert_equal original.message_id, Array(mail.references).first
    assert mail.text_part
    assert mail.html_part
    assert_equal [original.id, reply.id], LightekMail::Conversation.messages(account, reply).map(&:id)
  end

  test "reply all excludes the sender mailbox and never includes hidden recipients" do
    account = mailbox
    original = mail_record(account, to_addresses: [account.address, "visible@example.test"], cc_addresses: ["copy@example.test", "sender@example.test"], bcc_addresses: ["secret@example.test"])
    result = LightekMail::ComposeMessage.recipients(account, original, "reply_all")
    assert_equal ["sender@example.test"], result[:to]
    assert_equal %w[visible@example.test copy@example.test], result[:cc]
    assert_empty LightekMail::ComposeMessage.recipients(account, original, "forward")[:to]
    sent = mail_record(account, direction: "outbound", from_address: account.address, to_addresses: ["client@example.test"])
    assert_equal ["client@example.test"], LightekMail::ComposeMessage.recipients(account, sent, "reply")[:to]
  end

  test "reply honors a source Reply-To address" do
    account = mailbox
    original = mail_record(account)
    source = Mail.new(from: "sender@example.test", to: account.address, reply_to: "replies@example.test", subject: "Hello", body: "Hello")
    original.source.attach(io: StringIO.new(source.encoded), filename: "message.eml", content_type: "message/rfc822")
    assert_equal ["replies@example.test"], LightekMail::ComposeMessage.recipients(account, original, "reply")[:to]
  end

  test "forward quotes the original without linking itself to the original thread" do
    account = mailbox
    original = mail_record(account)
    attrs = LightekMail::ComposeMessage.attributes(account: account, original: original, mode: "forward", attributes: {text: "Please review", to: "someone@example.test", subject: "Fwd: Launch"})
    assert_equal "", attrs["in_reply_to"]
    assert_includes attrs["text"], "Forwarded message"
    assert_equal "Re: Launch plan", LightekMail::ComposeMessage.subject(mail_record(account, subject: "Re: Re: Launch plan"))
  end

  test "omitting the original removes its content and empty replies cannot send only a quote" do
    account = mailbox
    original = mail_record(account)
    attrs = LightekMail::ComposeMessage.attributes(account: account, original: original, include_original: false, attributes: {text: "New words"})
    refute_includes attrs["text"], "Original message"
    refute_includes attrs["html"], "Original message"
    assert_raises(ArgumentError) { LightekMail::ComposeMessage.attributes(account: account, original: original, attributes: {text: "", html: "<p><br></p>"}) }
    assert_raises(ActiveRecord::RecordNotFound) { LightekMail::ComposeMessage.attributes(account: mailbox, original: original, attributes: {text: "Private"}) }
  end

  test "saved designs still quote conversation history and remain mailbox scoped" do
    account = mailbox
    original = mail_record(account)
    template = account.templates.create!(name: "Welcome", subject: "Hello {{name}}", document: {body: "Thanks {{name}}"})
    attrs = LightekMail::ComposeMessage.attributes(account: account, original: original, attributes: {template_id: template.id, variables: {"name" => "Customer"}})
    assert_equal "Hello Customer", attrs["subject"]
    assert_includes attrs["html"], "Original message"
    assert_includes attrs["text"], "Thanks Customer"
    refute attrs.key?("template_id")
    assert_raises(ActiveRecord::RecordNotFound) { LightekMail::ComposeMessage.attributes(account: mailbox, attributes: {template_id: template.id}) }
  end

  test "HTML preserves safe styling but cannot execute scripts or load remote images by default" do
    html = '<p style="color:#123456;font-size:18px;line-height:1.5" onclick="steal()">Designed email</p><script>steal()</script><img src="https://tracker.test/pixel"><a href="javascript:steal()">Bad</a><iframe src="https://evil.test"></iframe>'
    clean = LightekMail::TemplateRenderer.clean_html(html)
    assert_includes clean, "color:#123456"
    refute_includes clean, "onclick"
    refute_includes clean, "steal()"
    refute_includes clean, "<iframe"
    blocked = LightekMail::MessageContent.document(clean)
    refute_includes blocked, "tracker.test"
    assert_includes blocked, "script-src &#39;none&#39;"
    allowed = LightekMail::MessageContent.document(clean, images: true)
    assert_includes allowed, "https://tracker.test/pixel"
  end

  test "older HTML source restores styling and strips active content" do
    account = mailbox
    original = mail_record(account, html_body: "<p>Saved without formatting</p>")
    source = Mail.new(from: "sender@example.test", to: account.address, content_type: "text/html", body: '<p style="color:#123456">Original design</p><script>bad()</script>')
    original.source.attach(io: StringIO.new(source.encoded), filename: "message.eml", content_type: "message/rfc822")
    content = LightekMail::MessageContent.new(original)
    assert_includes content.html, "color:#123456"
    assert_includes content.html, "Original design"
    refute_includes content.html, "bad()"
  end
  test "forwarded attachments retain their contents and respect mailbox ownership" do
    account = mailbox
    original = mail_record(account)
    original.attachments.attach(io: StringIO.new("Original attachment"), filename: "notes.txt", content_type: "text/plain")
    uploads = LightekMail::ComposeMessage.uploads(account: account, original: original, mode: "forward", include_attachments: true, uploads: [])
    draft = LightekMail::Submission.create!(account: account, draft: true, uploads: uploads, attributes: {to: "recipient@example.test", subject: "Forward", text: "Please review"})
    assert_equal "Original attachment", draft.attachments.first.download
    assert_empty LightekMail::ComposeMessage.uploads(account: account, original: original, mode: "reply", include_attachments: true, uploads: [])
    assert_raises(ActiveRecord::RecordNotFound) { LightekMail::ComposeMessage.uploads(account: mailbox, original: original, mode: "forward", include_attachments: true, uploads: []) }
  end

end
