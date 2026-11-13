require 'test_helper'
require 'minitest/mock'
class LightekMailboxLifecycleTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(first_name:'Team',last_name:'Mail',role:'super_admin',email_address:"team-#{SecureRandom.hex(4)}@example.test",password:"Mailbox-test-password-2026!")
    @domain = LightekMail::Domain.create!(user:@user,name:"team-#{SecureRandom.hex(4)}.test",verified_at:Time.current)
  end
  def mailbox(name)
    LightekMail::MailboxManagement.create!(user:@user,domain:@domain,local_part:name,display_name:name.capitalize)
  end
  def group(*members)
    LightekMail::MailboxManagement.save_group!(domain:@domain,local_part:'it',display_name:'IT team',member_ids:members.map(&:id))
  end
  def raw(to, body:'Hello team')
    Mail.new(from:'sender@example.test',to:to,subject:'Team update',body:body,message_id:"#{SecureRandom.hex(10)}@example.test",password:"Mailbox-test-password-2026!").encoded
  end
  test 'distribution envelope creates one private copy per member and retries use the original snapshot' do
    first,second,third = mailbox('andrew'),mailbox('marlon'),mailbox('third')
    list = group(first,second)
    source = raw(list.address)
    inbound = LightekMail::Inbound.accept!(raw:source,recipients:[list.address,first.address])
    assert_equal 1, first.messages.where(direction:'inbound').count
    assert_equal 1, second.messages.where(direction:'inbound').count
    assert_equal 0, list.messages.count
    assert_equal [list.address], first.messages.first.to_addresses
    assert first.messages.first.source.attached?
    LightekMail::MailboxManagement.save_group!(group:list,domain:@domain,local_part:'it',display_name:'IT',member_ids:[third.id])
    LightekMail::Inbound.accept!(raw:source,recipients:[list.address])
    LightekMail::Inbound.process!(inbound)
    assert_equal 0,third.messages.count
    LightekMail::Inbound.accept!(raw:raw(list.address),recipients:[list.address])
    assert_equal 1,third.messages.count
  end
  test 'a retired address cannot inherit old incoming delivery when recreated' do
    old = mailbox('andrew'); address = old.address
    incoming = LightekMail::Inbound.accept!(raw:raw(address),recipients:[address])
    old.retire!
    replacement = mailbox('andrew')
    LightekMail::Inbound.process!(incoming)
    assert_equal 0,replacement.messages.count
    assert_equal 1,old.messages.count
  end
  test 'spam and unavailable scans go to junk and cannot trigger automatic replies' do
    account = mailbox('andrew')
    scans = [{'action'=>'reject','score'=>12},nil]
    scans.each do |result|
      callable = ->(*) { result || raise(LightekMail::SpamScanner::Unavailable) }
      LightekMail::SpamScanner.stub(:scan!,callable) do
        LightekMail::AutoResponder.stub(:call, ->(*) { flunk 'Junk must not send an automatic reply' }) do
          LightekMail::Inbound.accept!(raw:raw(account.address),recipients:[account.address])
        end
      end
    end
    assert_equal 2,account.messages.where(junk:true).count
    assert_equal 0,account.messages.where(junk:false).count
    assert account.messages.last.spam_reason.present?
  end
end
