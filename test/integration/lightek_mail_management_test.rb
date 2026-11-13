require 'test_helper'
class LightekMailManagementTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(first_name:'Client',last_name:'Team',role:'client',email_address:"lifecycle-#{SecureRandom.hex(4)}@example.test",password:"Mailbox-test-password-2026!")
    @domain = LightekMail::Domain.create!(user:@user,name:"lifecycle-#{SecureRandom.hex(4)}.test",verified_at:Time.current)
    post '/session',params:{email_address:@user.email_address}
  end
  def mailbox(name) = LightekMail::MailboxManagement.create!(user:@user,domain:@domain,local_part:name,display_name:name.capitalize)
  test 'client creates an enabled mailbox renames it and deletes it without an enable step' do
    post '/dashboard/mail/accounts',params:{domain_id:@domain.id,local_part:'andrew',display_name:'Andrew'}
    assert_response :redirect
    account = LightekMail::Account.find_by!(address:"andrew@#{@domain.name}")
    assert account.enabled?
    patch "/dashboard/mail/accounts/#{account.id}",params:{display_name:'Andrew Support'}
    assert_response :redirect
    assert_equal 'Andrew Support',account.reload.display_name
    assert account.enabled?
    delete "/dashboard/mail/accounts/#{account.id}",params:{confirmation:account.address}
    assert_response :redirect
    assert account.reload.deleted_at
    refute account.enabled?
  end
  test 'group form creates an address with members and updates only owned groups' do
    first,second = mailbox('andrew'),mailbox('marlon')
    post '/dashboard/mail/groups',params:{domain_id:@domain.id,local_part:'it',display_name:'IT',member_ids:[first.id,second.id]}
    assert_response :redirect
    group = LightekMail::Access.groups(@user).find_by!(address:"it@#{@domain.name}")
    assert_equal [first.id,second.id].sort, group.members.pluck(:id).sort
    get '/dashboard/mail',params:{account_id:first.id,view:'settings'}
    assert_response :success
    assert_select '#mail-groups',text:/IT/
    assert_select 'select[name="spam_filter_level"]'
    assert_select 'form[action=?]',"/dashboard/mail/accounts/#{first.id}"
    patch "/dashboard/mail/groups/#{group.id}",params:{display_name:'Support',member_ids:[first.id]}
    assert_response :redirect
    assert_equal [first.id],group.reload.members.pluck(:id)
  end
  test 'junk is excluded from the inbox and owner can move it back' do
    account = mailbox('andrew')
    message = account.messages.create!(direction:'inbound',state:'inbox',from_address:'sender@example.test',to_addresses:[account.address],subject:'Junk test',text_body:'Body',message_id:'junk-test@example.test',junk:true)
    get '/dashboard/mail',params:{account_id:account.id}
    assert_response :success
    assert_select 'article[data-mail-item=?]',message.id.to_s,count:0
    get '/dashboard/mail',params:{account_id:account.id,folder:'junk'}
    assert_response :success
    assert_select 'article[data-mail-item=?]',message.id.to_s,count:1
    post "/dashboard/mail/accounts/#{account.id}/bulk",params:{message_ids:[message.id],operation:'not_spam'}
    assert_response :redirect
    refute message.reload.junk?
    patch "/dashboard/mail/accounts/#{account.id}",params:{spam_filter_level:'strict',blocked_senders:'spam.test'}
    assert_response :redirect
    assert_equal ['spam.test'],account.reload.blocked_senders
  end
end
