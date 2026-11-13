gem 'minitest', '~> 5.25'
require 'minitest/autorun'
require 'active_support/all'
require 'active_record'
require 'securerandom'
require 'digest'
ROOT = File.expand_path('../..', __dir__)
ActiveRecord::Base.establish_connection(adapter:'sqlite3',database:':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role }
  create_table(:lightek_mail_domains) { |t| t.integer :user_id; t.string :name; t.string :verification_token; t.datetime :verified_at }
  create_table(:lightek_mail_accounts) do |t|
    t.integer :user_id; t.integer :domain_id; t.integer :auto_template_id
    t.string :address; t.string :display_name; t.boolean :enabled, default:false
    t.integer :daily_limit,default:100; t.integer :minute_limit,default:5; t.integer :hour_limit,default:25; t.integer :storage_limit,default:1048576
    t.datetime :suspended_at; t.boolean :auto_reply_enabled,default:false; t.string :token_digest; t.string :token_hint
  end
  add_index :lightek_mail_accounts,:address,unique:true
  create_table(:lightek_mail_sending_policies) { |t| t.boolean :sending_enabled,default:false; t.string :stop_reason }
  create_table(:lightek_mail_envelopes) { |t| t.json :recipients,default:[] }
  create_table(:lightek_mail_templates) { |t| t.integer :account_id }
  create_table(:lightek_mail_messages) { |t| t.integer :account_id; t.string :subject }
  create_table(:lightek_mail_customer_suspensions) { |t| t.integer :user_id }
end
# The source migration is applied to this public ActiveRecord fixture. Local
# development can use AR 7.2; CI uses the app's AR 8 compatibility level.
version = ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'
path = ROOT+'/db/migrate/20261113140000_add_lightek_mailbox_management.rb'
eval(File.read(path).sub('Migration[8.0]',"Migration[#{version}]"),TOPLEVEL_BINDING,path)
AddLightekMailboxManagement.new.migrate(:up)
class ApplicationRecord < ActiveRecord::Base; self.abstract_class = true; end
class User < ApplicationRecord
  def can_access_feature?(*) = true
end
module LightekMail
  class Template < ApplicationRecord; self.table_name = 'lightek_mail_templates'; end
  class Message < ApplicationRecord; self.table_name = 'lightek_mail_messages'; end
  class CustomerSuspension < ApplicationRecord; self.table_name = 'lightek_mail_customer_suspensions'; end
end
%w[domain account group_member].each { |file| require ROOT+"/app/models/lightek_mail/#{file}" }
%w[access mailbox_management recipient_directory spam_filter].each { |file| require ROOT+"/app/services/lightek_mail/#{file}" }
class LightekMailboxManagementTest < Minitest::Test
  def setup
    @user = User.create!(role:'client')
    @domain = LightekMail::Domain.create!(user:@user,name:"client-#{SecureRandom.hex(4)}.test",verified_at:Time.current)
  end
  def mailbox(name)
    LightekMail::MailboxManagement.create!(user:@user,domain:@domain,local_part:name,display_name:name.capitalize)
  end
  def test_new_mailboxes_are_automatically_enabled_and_exported
    account = mailbox('andrew')
    assert account.enabled?
    assert account.sending_ready?
    assert_includes LightekMail::RecipientDirectory.addresses, account.address
  end
  def test_group_resolves_to_two_individual_mailboxes_without_duplicates
    first, second = mailbox('andrew'),mailbox('marlon')
    group = LightekMail::MailboxManagement.save_group!(domain:@domain,local_part:'it',display_name:'IT',member_ids:[first.id,second.id,first.id])
    assert_equal [first.id,second.id].sort, LightekMail::RecipientDirectory.resolve!(group.address).sort
    assert_includes LightekMail::RecipientDirectory.addresses, group.address
    refute_includes LightekMail::Access.accounts(@user), group
  end
  def test_group_rejects_cross_customer_members_and_nested_groups
    own = mailbox('andrew')
    other = User.create!(role:'client')
    domain = LightekMail::Domain.create!(user:other,name:"other-#{SecureRandom.hex(4)}.test",verified_at:Time.current)
    foreign = LightekMail::MailboxManagement.create!(user:other,domain:domain,local_part:'private',display_name:'Private')
    assert_raises(ArgumentError) { LightekMail::MailboxManagement.save_group!(domain:@domain,local_part:'it',display_name:'IT',member_ids:[foreign.id]) }
    group = LightekMail::MailboxManagement.save_group!(domain:@domain,local_part:'it',display_name:'IT',member_ids:[own.id])
    assert_raises(ArgumentError) { LightekMail::MailboxManagement.save_group!(domain:@domain,local_part:'nested',display_name:'Nested',member_ids:[group.id]) }
  end
  def test_retirement_revokes_token_routes_membership_and_keeps_history_isolated
    account = mailbox('andrew'); original = account.address; token = account.rotate_token!
    group = LightekMail::MailboxManagement.save_group!(domain:@domain,local_part:'it',display_name:'IT',member_ids:[account.id])
    old = account.messages.create!(subject:'Retained history')
    account.retire!
    assert account.deleted_at
    refute account.enabled?
    assert_nil LightekMail::Account.authenticate(token)
    refute_includes LightekMail::Access.accounts(@user), account
    refute_includes LightekMail::RecipientDirectory.addresses, original
    refute_includes LightekMail::RecipientDirectory.addresses, group.address
    assert LightekMail::Message.exists?(old.id)
    replacement = mailbox('andrew')
    assert_equal original,replacement.address
    assert_empty replacement.messages
  end
  def test_unverified_domain_does_not_become_a_receiving_route
    @domain.update!(verified_at:nil)
    account = mailbox('pending')
    assert account.enabled?
    refute account.sending_ready?
    refute_includes LightekMail::RecipientDirectory.addresses,account.address
  end
  def test_spam_settings_are_validated
    account = mailbox('andrew')
    refute account.update(allowed_senders:['https://bad.test'],spam_filter_level:'off')
    assert account.update(allowed_senders:['trusted.test'],spam_filter_level:'strict')
  end
  def test_spam_filter_uses_server_verdict_and_per_mailbox_lists
    account = mailbox('andrew')
    classify = ->(score,action='no action') { LightekMail::SpamFilter.classify(account:account,sender:'sender@trusted.test',scan:{'action'=>action,'score'=>score}) }
    refute classify.call(4.5)[:junk]
    account.update!(spam_filter_level:'strict')
    assert classify.call(4.5)[:junk]
    account.update!(allowed_senders:['trusted.test'])
    refute classify.call(4.5)[:junk]
    assert classify.call(8,'reject')[:junk]
    assert LightekMail::SpamFilter.classify(account:account,sender:'sender@trusted.test',scan:nil)[:junk]
    account.update!(blocked_senders:['sender@trusted.test'])
    assert classify.call(0)[:junk]
  end
end
