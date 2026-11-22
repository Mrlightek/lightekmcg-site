gem 'minitest', '~> 5.25'
require 'minitest/autorun'
require 'minitest/mock'
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
  create_table(:lightek_mail_messages) do |t|
    t.integer :account_id
    t.string :subject
    t.string :direction, default: 'inbound'
    t.string :state
    t.string :text_body
    %i[trashed archived starred].each { |flag| t.boolean flag, default: false }
    t.datetime :read_at
    t.timestamps
  end
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
  class DeliverJob
    def self.perform_later(*) = raise("Expected a controlled delivery job")
  end
  class Template < ApplicationRecord; self.table_name = 'lightek_mail_templates'; end
  class Message < ApplicationRecord; self.table_name = 'lightek_mail_messages'; end
  class CustomerSuspension < ApplicationRecord; self.table_name = 'lightek_mail_customer_suspensions'; end
end
%w[domain account group_member].each { |file| require ROOT+"/app/models/lightek_mail/#{file}" }
%w[access mailbox_management recipient_directory receiving_status spam_filter message_folder message_flag search].each { |file| require ROOT+"/app/services/lightek_mail/#{file}" }
require ROOT+'/app/services/nevaeh_os/platform_actions'
class LightekMailboxManagementTest < Minitest::Test
  def setup
    @user = User.create!(role:'client')
    @domain = LightekMail::Domain.create!(user:@user,name:"client-#{SecureRandom.hex(4)}.test",verified_at:Time.current)
  end
  def mailbox(name)
    LightekMail::MailboxManagement.create!(user:@user,domain:@domain,local_part:name,display_name:name.capitalize)
  end
  def test_nevaeh_searches_and_flags_only_the_selected_mailbox
    account = mailbox('primary')
    second = mailbox('other')
    message = account.messages.create!(subject: 'Proposal', text_body: 'Private body')
    archived = account.messages.create!(subject: 'Proposal', archived: true)
    foreign = second.messages.create!(subject: 'Proposal')
    search = NevaehOs::PlatformActions.command('mail.message.search',
      {'mailbox_id'=>account.id, 'folder'=>'inbox', 'query'=>'subject:Proposal'})
    receipt = NevaehOs::PlatformActions.perform!(actor: @user, command: search, action_id: 1)
    assert_equal [message.id], receipt.fetch('records').pluck('id')
    refute_includes receipt.to_json, 'Private body'
    assert_includes LightekMail::MessageFolder.scope(account, 'archived'), archived

    params = {'mailbox_id'=>account.id, 'message_id'=>foreign.id, 'flag'=>'starred', 'value'=>true}
    flag = NevaehOs::PlatformActions.command('mail.message.flag', params)
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::PlatformActions.perform!(actor: @user, command: flag, action_id: 2) }
    refute foreign.reload.starred?
    flag = NevaehOs::PlatformActions.command('mail.message.flag', params.merge('message_id'=>message.id))
    NevaehOs::PlatformActions.perform!(actor: @user, command: flag, action_id: 3)
    assert message.reload.starred?
    assert_raises(ArgumentError) do
      NevaehOs::PlatformActions.command('mail.draft.send', {'mailbox_id'=>account.id, 'message_id'=>message.id, 'confirmed'=>false})
    end
  end

  def test_new_mailboxes_are_automatically_enabled_and_exported
    account = mailbox('andrew')
    assert account.enabled?
    assert account.sending_ready?
    assert_includes LightekMail::RecipientDirectory.addresses, account.address
  end
  def test_nevaeh_checks_receiving_dns_only_for_an_accessible_mailbox
    account = mailbox('andrew')
    command = NevaehOs::PlatformActions.command('mail.mailbox.receiving.check', {'mailbox_id'=>account.id})
    outsider = User.create!(role:'client')
    query = Minitest::Mock.new
    query.expect(:timeouts=, 2, [2])
    expected_mx = ENV.fetch('LIGHTEK_MAIL_HOST', 'mail.lightekmcg.com')
    query.expect(:getresources, [Resolv::DNS::Resource::IN::MX.new(10, expected_mx)],
      ["#{@domain.name}.", Resolv::DNS::Resource::IN::MX])

    Resolv::DNS.stub(:open, ->(&block) { block.call(query) }) do
      assert_raises(ActiveRecord::RecordNotFound) do
        NevaehOs::PlatformActions.perform!(actor: outsider, command: command, action_id: 1)
      end
      result = NevaehOs::PlatformActions.perform!(actor: @user, command: command, action_id: 2)
      assert_equal account.id, result.fetch('mailbox_id')
      assert_equal true, result.fetch('mx_ready')
    end
    query.verify
  end

  def test_resuming_mail_queues_only_outbound_messages_with_no_submission_in_progress
    account = mailbox('outbox')
    message = account.messages.create!(subject: 'Queued message', direction: 'outbound', state: 'queued')
    action = NevaehOs::PlatformActions.command('mail.message.resume_queued',
      {'mailbox_id'=>account.id, 'message_id'=>message.id})
    job = ->(id) { assert_equal message.id, id; Struct.new(:job_id).new("queued-123") }
    LightekMail::DeliverJob.stub(:perform_later, job) do
      assert_equal "queued-123", NevaehOs::PlatformActions.perform!(actor: @user, command: action, action_id: 5).fetch('job_id')
    end
    message.update!(state: 'uncertain')
    assert_raises(ArgumentError) { NevaehOs::PlatformActions.perform!(actor: @user, command: action, action_id: 6) }
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
