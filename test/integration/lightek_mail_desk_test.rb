require "test_helper"
require_relative "lightek_mail_conversations_test"

class LightekMailConversationsTest
  test "workspace provides accessible panes and moves administration into settings" do
    user, account, original = workspace
    login(user)
    get '/dashboard/mail', params: {account_id: account.id}
    assert_response :success
    assert_select '[data-mail-app]'
    assert_select '[data-mail-reader-frame][title="Selected conversation"]'
    assert_select '[data-mail-compose-dock][hidden]'
    assert_select '[name="message_ids[]"]', count: 1
    assert_select '#mail-designs', count: 0
    get '/dashboard/mail', params: {account_id: account.id, view: 'settings'}
    assert_response :success
    assert_select '#mail-designs'
    assert_select 'summary', text: 'Automatic replies & mailbox settings'
  end

  test "advanced search combines operators phrases dates and attachments" do
    user, account, original = workspace
    original.attachments.attach(io: StringIO.new('hello'), filename: 'hello.txt', content_type: 'text/plain')
    account.messages.create!(direction: 'inbound', state: 'inbox', from_address: 'other@example.test', subject: 'Other note', text_body: 'Unrelated', message_id: SecureRandom.uuid)
    login(user)
    get '/dashboard/mail', params: {account_id: account.id, folder: 'all', q: 'from:sender subject:"Conversation history" has:attachment is:unread after:2020-01-01 before:2099-01-01'}
    assert_response :success
    assert_select '.message-row', count: 1
    assert_select '.message-subject', text: 'Conversation history'
    get '/dashboard/mail', params: {account_id: account.id, q: 'from:other is:starred'}
    assert_select '.message-row', count: 0
    get '/dashboard/mail', params: {account_id: account.id, q: "%' OR 1=1 --"}
    assert_select '.message-row', count: 0
  end

  test "pagination is stable bounded and retains searches" do
    user, account, original = workspace
    42.times { |i| account.messages.create!(direction: 'inbound', state: 'inbox', from_address: 'sender@example.test', subject: "Page #{i}", text_body: 'Pagination', message_id: SecureRandom.uuid) }
    login(user)
    get '/dashboard/mail', params: {account_id: account.id, q: 'Pagination'}
    assert_select '.message-row', count: 40
    assert_select 'a[aria-label="Next page"]'
    get '/dashboard/mail', params: {account_id: account.id, q: 'Pagination', page: 2}
    assert_select '.message-row', count: 2
    assert_select 'a[aria-label="Previous page"]'
    get '/dashboard/mail', params: {account_id: account.id, q: 'Pagination', page: 999999}
    assert_select '.message-row', count: 2
  end

  test "bulk operations validate the full mailbox scoped selection atomically" do
    user, account, original = workspace
    _other_user, _other, secret = workspace
    login(user)
    post "/dashboard/mail/accounts/#{account.id}/bulk", params: {message_ids: [original.id, secret.id], operation: 'trash'}
    assert_response :not_found
    refute original.reload.trashed?
    refute secret.reload.trashed?
    post "/dashboard/mail/accounts/#{account.id}/bulk", params: {message_ids: [original.id], operation: 'destroy'}
    assert_response :redirect
    refute original.reload.trashed?
    post "/dashboard/mail/accounts/#{account.id}/bulk", params: {message_ids: [], operation: 'trash'}
    assert_response :redirect
    refute original.reload.trashed?
  end

  test "bulk archive undo restores prior values and cannot overwrite a later change" do
    user, account, original = workspace
    login(user)
    post "/dashboard/mail/accounts/#{account.id}/bulk", params: {message_ids: [original.id], operation: 'archive'}
    assert_response :redirect
    assert original.reload.archived?
    follow_redirect!
    token = css_select('input[name=undo_token]').first['value']
    post "/dashboard/mail/accounts/#{account.id}/undo", params: {undo_token: token}
    assert_response :redirect
    refute original.reload.archived?
    # Replaying the same token cannot reverse subsequent unrelated state.
    original.update!(starred: true)
    post "/dashboard/mail/accounts/#{account.id}/undo", params: {undo_token: token}
    assert_response :redirect
    assert original.reload.starred?
    refute original.archived?
    post "/dashboard/mail/accounts/#{account.id}/undo", params: {undo_token: 'forged'}
    assert_response :redirect
    refute original.reload.archived?
  end

  test "bulk read and unread undo tolerate database timestamp precision" do
    user, account, original = workspace
    login(user)
    post "/dashboard/mail/accounts/#{account.id}/bulk", params: {message_ids: [original.id], operation: 'read'}
    assert original.reload.read_at
    follow_redirect!
    token = css_select('input[name=undo_token]').first['value']
    post "/dashboard/mail/accounts/#{account.id}/undo", params: {undo_token: token}
    assert_nil original.reload.read_at
  end

  test "preview only permits passive attachment types and enforces ownership" do
    user, account, original = workspace
    original.attachments.attach(io: StringIO.new('Attachment text'), filename: 'note.txt', content_type: 'text/plain')
    original.attachments.attach(io: StringIO.new('<script>alert(1)</script>'), filename: 'unsafe.html', content_type: 'text/html')
    login(user)
    safe, unsafe = original.attachments.to_a
    get "/dashboard/mail/accounts/#{account.id}/messages/#{original.id}/attachments/#{safe.id}", params: {preview: '1'}
    assert_response :success
    assert_includes response.headers['Content-Disposition'], 'inline'
    assert_includes response.headers['Content-Security-Policy'], 'sandbox'
    assert_equal 'nosniff', response.headers['X-Content-Type-Options']
    get "/dashboard/mail/accounts/#{account.id}/messages/#{original.id}/attachments/#{unsafe.id}", params: {preview: '1'}
    assert_includes response.headers['Content-Disposition'], 'attachment'
    assert_equal 'application/octet-stream', response.media_type
    other_user, = workspace
    login(other_user)
    get "/dashboard/mail/accounts/#{account.id}/messages/#{original.id}/attachments/#{safe.id}", params: {preview: '1'}
    assert_response :not_found
  end

  test "embedded composer preserves workspace mode after validation and saving" do
    user, account, original = workspace
    login(user)
    get "/dashboard/mail/accounts/#{account.id}/compose", params: {workspace: '1'}
    assert_select 'input[name=workspace][value="1"]'
    post "/dashboard/mail/accounts/#{account.id}/messages", params: {workspace: '1', to: 'bad', subject: 'Workspace', text: 'Keep me', commit_action: 'draft'}
    assert_response :unprocessable_entity
    assert_select 'input[name=workspace][value="1"]'
    post "/dashboard/mail/accounts/#{account.id}/messages", params: {workspace: '1', to: original.from_address, subject: 'Workspace', text: 'Keep me', commit_action: 'draft'}
    assert_response :redirect
    follow_redirect!
    assert_select '[data-mail-composed=draft]'
  end
  test "a full page bulk action keeps its undo within cookie limits" do
    user, account, original = workspace
    39.times { |i| account.messages.create!(direction: 'inbound', state: 'inbox', from_address: 'sender@example.test', subject: "Bulk #{i}", text_body: 'Bulk', message_id: SecureRandom.uuid) }
    login(user)
    post "/dashboard/mail/accounts/#{account.id}/bulk", params: {message_ids: account.messages.pluck(:id), operation: 'trash'}
    assert_response :redirect
    assert_equal 40, account.messages.where(trashed: true).count
    assert_operator response.headers['Set-Cookie'].to_s.bytesize, :<, 4096
    follow_redirect!
    token = css_select('input[name=undo_token]').first['value']
    post "/dashboard/mail/accounts/#{account.id}/undo", params: {undo_token: token}
    assert_equal 0, account.messages.where(trashed: true).count
  end

end
