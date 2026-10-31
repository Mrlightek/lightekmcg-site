require "test_helper"

class LightekMailConversationsTest < ActionDispatch::IntegrationTest
  def workspace
    user = User.create!(first_name: "Reader", last_name: "Mail", role: "client", email_address: "reader-#{SecureRandom.hex(5)}@example.test", password: "Mail-test-2026-password!")
    user.grant_feature!("mail") if user.respond_to?(:grant_feature!)
    domain = LightekMail::Domain.create!(user: user, name: "reader-#{SecureRandom.hex(5)}.test", verified_at: Time.current)
    account = LightekMail::Account.create!(user: user, domain: domain, address: "hello@#{domain.name}", display_name: "Reader team", enabled: true)
    original = account.messages.create!(direction: "inbound", state: "inbox", from_address: "sender@example.test", to_addresses: [account.address, "visible@example.test"], cc_addresses: ["copy@example.test"], subject: "Conversation history", text_body: "Previous text to keep", html_body: '<p style="color:#123456">Previous <strong>formatted text</strong></p><img src="https://images.example.test/photo.png">', message_id: "#{SecureRandom.hex(10)}@example.test")
    [user, account, original]
  end

  def login(user)
    post "/session", params: {email_address: user.email_address, password: "Mail-test-2026-password!"}
    assert_response :redirect
  end

  test "reply composer displays the previous message and prepares visible reply-all recipients" do
    user, account, original = workspace
    login(user)
    get "/dashboard/mail/accounts/#{account.id}/compose", params: {reply_id: original.id, mode: "reply_all"}
    assert_response :success
    assert_select '.original-context h2', text: "Conversation history"
    assert_select 'iframe[data-mail-frame]', count: 1
    assert_select '[contenteditable=true][role=textbox]', count: 1
    assert_select 'input[name=to][value="sender@example.test"]'
    assert_select 'input[name=cc][value="visible@example.test, copy@example.test"]'
    assert_select 'input[name=include_original][checked]'
    assert_select 'input[name=subject][value="Re: Conversation history"]'
  end

  test "saved formatted reply contains original text and HTML and renders as a conversation" do
    user, account, original = workspace
    login(user)
    attrs = {rich_text_enabled: "1", reply_id: original.id, include_original: "1", to: original.from_address, subject: "Re: Conversation history", html: "<p>A <strong>formatted reply</strong></p>", text: "A formatted reply", commit_action: "draft", idempotency_key: "conversation_browser_123"}
    2.times { post "/dashboard/mail/accounts/#{account.id}/messages", params: attrs; assert_response :redirect }
    assert_equal 2, account.messages.count
    reply = account.messages.order(:id).last
    assert_includes reply.text_body, "> Previous text to keep"
    assert_includes reply.html_body, "<strong>formatted reply</strong>"
    assert_includes reply.html_body, "Previous <strong>formatted text</strong>"
    refute_includes reply.html_body, 'https://images.example.test/photo.png'
    assert_equal "<#{original.message_id}>", reply.in_reply_to
    get "/dashboard/mail/accounts/#{account.id}/messages/#{reply.id}"
    assert_response :success
    assert_select '.conversation-card', count: 2
    assert_select '.current-message iframe.email-canvas', count: 1
    assert_select '.plain-text-version summary', text: "Plain-text version"
  end

  test "reader loads HTML first and remote images require explicit opt-in" do
    user, account, original = workspace
    login(user)
    get "/dashboard/mail/accounts/#{account.id}/messages/#{original.id}"
    assert_response :success
    assert_select '.current-message iframe.email-canvas' do |frames|
      refute_includes frames.first['srcdoc'], 'https://images.example.test/photo.png'
      assert_includes frames.first['srcdoc'], 'color:#123456'
    end
    assert_select '.image-controls a', text: 'Load remote images'
    get "/dashboard/mail/accounts/#{account.id}/messages/#{original.id}", params: {images: '1'}
    assert_response :success
    assert_select 'iframe.email-canvas' do |frames|
      assert_includes frames.first['srcdoc'], 'https://images.example.test/photo.png'
    end
  end

  test "failed reply preserves formatting original context and recipient fields" do
    user, account, original = workspace
    login(user)
    post "/dashboard/mail/accounts/#{account.id}/messages", params: {rich_text_enabled: '1', reply_id: original.id, include_original: '1', to: 'invalid', subject: 'Re: Conversation history', text: 'Keep my reply', html: '<p>Keep <b>my reply</b></p>', commit_action: 'draft'}
    assert_response :unprocessable_entity
    assert_select '.original-context h2', text: 'Conversation history'
    assert_select 'textarea[name=html]', text: '<p>Keep <b>my reply</b></p>'
    assert_select 'textarea[name=text]', text: 'Keep my reply'
    assert_select 'input[name=include_original][checked]'
    assert_equal 1, account.messages.count
  end

  test "draft copies do not append original history a second time" do
    user, account, original = workspace
    login(user)
    draft = LightekMail::Submission.create!(account: account, draft: true, attributes: LightekMail::ComposeMessage.attributes(account: account, original: original, attributes: {to: original.from_address, subject: 'Re: Conversation history', text: 'Draft reply'}))
    get "/dashboard/mail/accounts/#{account.id}/compose", params: {draft_id: draft.id}
    assert_response :success
    assert_select 'input[name=include_original][checked]', count: 0
    assert_select '.original-context h2', text: 'Conversation history'
  end

  test "reply and thread views cannot read another mailbox or quote its message" do
    user, account, original = workspace
    _other_user, other, private_message = workspace
    private_message.update!(message_id: original.message_id, text_body: 'Private other mailbox')
    login(user)
    get "/dashboard/mail/accounts/#{account.id}/messages/#{original.id}"
    assert_response :success
    refute_includes response.body, 'Private other mailbox'
    get "/dashboard/mail/accounts/#{account.id}/compose", params: {reply_id: private_message.id}
    assert_response :not_found
    post "/dashboard/mail/accounts/#{account.id}/messages", params: {reply_id: private_message.id, include_original: '1', to: 'recipient@example.test', subject: 'No', text: 'No', commit_action: 'draft'}
    assert_response :not_found
    get "/dashboard/mail/accounts/#{other.id}/messages/#{private_message.id}"
    assert_response :not_found
  end

  test "unread starred and archive views filter messages within the active mailbox" do
    user, account, original = workspace
    original.update!(starred: true)
    read = account.messages.create!(direction: 'inbound', state: 'inbox', from_address: 'other@example.test', subject: 'Read archive', message_id: SecureRandom.uuid, read_at: Time.current, archived: true)
    login(user)
    get '/dashboard/mail', params: {account_id: account.id, folder: 'unread'}
    assert_response :success
    assert_select '.message-row', count: 1
    get '/dashboard/mail', params: {account_id: account.id, folder: 'starred'}
    assert_response :success
    assert_select '.message-subject', text: 'Conversation history'
    get '/dashboard/mail', params: {account_id: account.id, folder: 'archived'}
    assert_response :success
    assert_select '.message-subject', text: 'Read archive'
  end
  test "plain fallback edits cannot accidentally send stale hidden HTML" do
    user, account, original = workspace
    login(user)
    post "/dashboard/mail/accounts/#{account.id}/messages", params: {rich_text_enabled: '0', to: original.from_address, subject: 'Plain fallback', text: 'Updated plain message', html: '<p>Old hidden message</p>', commit_action: 'draft'}
    assert_response :redirect
    draft = account.messages.order(:id).last
    assert_includes draft.html_body, 'Updated plain message'
    refute_includes draft.html_body, 'Old hidden message'
  end

end
