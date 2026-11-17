require_relative 'lightek_mailbox_management_test'
ActiveRecord::Schema.define do
  add_column :users, :lightek_email_address, :string
end
path = ROOT + '/db/migrate/20261117032000_add_member_brand_mailboxes.rb'
eval(File.read(path).sub('Migration[8.0]', "Migration[#{version = ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]"), TOPLEVEL_BINDING, path)
AddMemberBrandMailboxes.new.migrate(:up)
require ROOT + '/app/models/lightek_pwa/launch_settings'
require ROOT + '/app/services/lightek_email_provisioning_service'
class User
  def full_name = 'A Member'
end
class PwaMemberEmailTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @old_flag = ENV['LIGHTEK_MEMBER_EMAIL_ENABLED']
    ENV['LIGHTEK_MEMBER_EMAIL_ENABLED'] = 'true'
    @operator=User.create!(role:'super_admin')
    @domain=LightekMail::Domain.create!(user:@operator,name:LightekEmailProvisioningService::DOMAIN,verified_at:Time.current)
    @user=User.create!(role:'client')
  end
  def teardown
    ENV['LIGHTEK_MEMBER_EMAIL_ENABLED']=@old_flag
    ActiveRecord::Base.connection.rollback_transaction
  end
  def test_unconfirmed_signups_are_not_given_fake_addresses
    assert_nil LightekEmailProvisioningService.provision_for!(@user)
    assert_nil @user.reload.lightek_email_address
    assert_equal 0,LightekMail::Account.where(user:@user).count
  end
  def test_confirmation_creates_a_real_scoped_mailbox_with_free_limits
    address=LightekEmailProvisioningService.confirm!(@user)
    account=LightekMail::Account.find_by!(user:@user,address:address)
    assert account.brand_member?
    assert account.enabled?
    assert account.sending_ready?
    assert_equal 20,account.daily_limit
    assert_equal 250.megabytes,account.storage_limit
    assert_includes LightekMail::RecipientDirectory.addresses,address
    assert_includes LightekMail::Access.accounts(@user),account
    assert_empty LightekMail::Access.domains(@user)
    assert_equal address,LightekEmailProvisioningService.provision_for!(@user)
    assert_equal 1,LightekMail::Account.where(user:@user).count
  end
  def test_same_names_allocate_unique_addresses_and_cannot_claim_another_mailbox
    first=LightekEmailProvisioningService.confirm!(@user)
    other=User.create!(role:'client')
    second=LightekEmailProvisioningService.confirm!(other)
    refute_equal first,second
    refute_includes LightekMail::Access.accounts(other),LightekMail::Account.find_by!(address:first)
    assert_raises(ActiveRecord::RecordInvalid){LightekMail::Account.create!(user:other,domain:@domain,address:'stolen@'+@domain.name,display_name:'Stolen',brand_member:true,enabled:true)}
  end
  def test_unverified_or_nonoperator_brand_domain_cannot_issue_member_mail
    @domain.update!(verified_at:nil)
    assert_raises(LightekEmailProvisioningService::Unavailable){LightekEmailProvisioningService.confirm!(@user)}
    assert_nil @user.reload.lightek_email_confirmed_at
    assert_nil @user.lightek_email_address
    assert_equal 0,LightekMail::Account.where(user:@user).count
  end
  def test_closed_member_email_does_not_change_the_user
    ENV['LIGHTEK_MEMBER_EMAIL_ENABLED']='false'
    assert_raises(LightekEmailProvisioningService::Unavailable){LightekEmailProvisioningService.confirm!(@user)}
    assert_nil @user.reload.lightek_email_confirmed_at
  end
end
