require "test_helper"
class LightekMailTest < ActionDispatch::IntegrationTest
  setup { LightekMail::SendingPolicy.create_or_find_by!(id: 1).update!(sending_enabled: true) }
  def actor(role = "super_admin")
    user = User.create!(first_name:"Mail",last_name:"User",role:role,email_address:"entitled-#{SecureRandom.hex(6)}@example.test",password:"Mail-test-2026-password!")
    user.grant_feature!("mail") if role == "client" && user.respond_to?(:grant_feature!)
    user
  end
  def mailbox(user = actor)
    domain = LightekMail::Domain.create!(user:user,name:"customer-#{SecureRandom.hex(6)}.test",verified_at:Time.current)
    LightekMail::Account.create!(user:user,domain:domain,address:"care@#{domain.name}",display_name:"Customer care",enabled:true)
  end
  def login(user)
    post "/session",params:{email_address:user.email_address,password:"Mail-test-2026-password!"}
    assert_response :redirect
  end
  test "API requires a ready mailbox token and idempotency key" do
    account = mailbox
    headers = {"Authorization"=>"Bearer #{account.rotate_token!}","Idempotency-Key"=>"fixture_request_001"}
    body = {to:"recipient@example.test",subject:"Hello",text:"From the HTTPS relay"}
    post "/api/lightek-mail/messages",params:body,as: :json
    assert_response :unauthorized
    2.times { post "/api/lightek-mail/messages",params:body,headers:headers,as: :json;assert_response :accepted }
    assert_equal 1,account.messages.count
    id = response.parsed_body.fetch("id")
    get "/api/lightek-mail/messages/#{id}",headers:headers
    assert_response :success
    refute response.parsed_body.key?("text")
    other = mailbox
    get "/api/lightek-mail/messages/#{id}",headers:{"Authorization"=>"Bearer #{other.rotate_token!}"}
    assert_response :not_found
    account.update!(enabled:false)
    post "/api/lightek-mail/messages",params:body,headers:headers,as: :json
    assert_response :unauthorized
  end
  test "inbound rejects missing or incorrect secret before accepting raw content" do
    old = ENV["LIGHTEK_MAIL_INGRESS_TOKEN"]
    ENV["LIGHTEK_MAIL_INGRESS_TOKEN"] = "fixture-ingress-#{'a'*40}"
    post "/api/lightek-mail/inbound",params:"From: attacker@example.test\r\n\r\nnot accepted",headers:{"Content-Type"=>"message/rfc822"}
    assert_response :unauthorized
  ensure
    ENV["LIGHTEK_MAIL_INGRESS_TOKEN"]=old
  end
  test "mail workspace and template preview are scoped to the signed-in owner" do
    account, other = mailbox(actor("client")), mailbox(actor("client"))
    login(account.user)
    get "/dashboard/mail",params:{account_id:account.id}
    assert_response :success
    assert_select "h1",text:"Inbox"
    get "/dashboard/mail",params:{account_id:other.id}
    assert_response :not_found
    post "/dashboard/mail/accounts/#{account.id}/templates/preview",params:{document:{heading:"Hi {{name}}",body:"Test preview"}},as: :json
    assert_response :success
    assert_includes response.parsed_body.fetch("html"),"Hi Tiff"
    post "/dashboard/mail/accounts/#{other.id}/templates/preview",params:{document:{body:"private"}},as: :json
    assert_response :not_found
  end
  test "a client cannot enable sending or increase its own quota" do
    account=mailbox(actor("client"));account.update!(enabled:false)
    login(account.user)
    patch "/dashboard/mail/accounts/#{account.id}",params:{enabled:"1",daily_limit:5000,storage_limit:999999999999,auto_reply_enabled:"0"}
    assert_response :redirect
    refute account.reload.enabled?
    assert_equal 100,account.daily_limit
    assert_equal 1_073_741_824,account.storage_limit
  end
  test "original email downloads and permanent deletion require mailbox ownership" do
    account = mailbox(actor("client"))
    mail = Mail.new(from:"sender@example.test",to:account.address,subject:"Private attachment",body:"Private message")
    inbound = LightekMail::Inbound.accept!(raw:mail.encoded,recipients:[account.address])
    inbound.route
    record = account.messages.first
    login(account.user)
    get "/dashboard/mail/accounts/#{account.id}/messages/#{record.id}"
    assert_response :success
    get "/dashboard/mail/accounts/#{account.id}/messages/#{record.id}/attachments/source"
    assert_response :success
    assert_includes response.headers["Content-Disposition"],"attachment"
    login(actor("client"))
    get "/dashboard/mail/accounts/#{account.id}/messages/#{record.id}/attachments/source"
    assert_response :not_found
    login(account.user)
    patch "/dashboard/mail/accounts/#{account.id}/messages/#{record.id}/flag",params:{flag:"trashed",value:"1"}
    assert_response :redirect
    delete "/dashboard/mail/accounts/#{account.id}/messages/#{record.id}"
    assert_response :redirect
    refute account.messages.exists?(record.id)
  end

  test "browser compose preserves Cc Bcc and deduplicates submission retries" do
    account = mailbox
    login(account.user)
    body = {to: " first@example.test, second@example.test ", cc: "copy@example.test", bcc: "blind@example.test", subject: "Launch", text: "Ready", commit_action: "draft", idempotency_key: "web_browser_retry_123"}
    2.times do
      post "/dashboard/mail/accounts/#{account.id}/messages", params: body
      assert_response :redirect
    end
    assert_equal 1, account.messages.count
    message = account.messages.last
    assert_equal %w[first@example.test second@example.test], message.to_addresses
    assert_equal ["copy@example.test"], message.cc_addresses
    assert_equal ["blind@example.test"], message.bcc_addresses
  end

  test "failed compose preserves message and unauthorized account ids do not fall back" do
    account, other = mailbox(actor("client")), mailbox(actor("client"))
    login(account.user)
    post "/dashboard/mail/accounts/#{account.id}/messages", params: {to: "invalid", subject: "Keep my work", text: "Unsaved message", commit_action: "draft"}
    assert_response :unprocessable_entity
    assert_select "textarea[name=text]", text: "Unsaved message"
    post "/dashboard/mail/accounts/#{other.id}/receiving-check"
    assert_response :not_found
    post "/dashboard/mail/accounts/#{other.id}/messages", params: {to: "recipient@example.test", subject: "No", text: "No", commit_action: "draft"}
    assert_response :not_found
    assert_equal 0, other.messages.count
  end

end
