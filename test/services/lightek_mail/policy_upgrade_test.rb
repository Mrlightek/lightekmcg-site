require "test_helper"
require_relative "../../../db/migrate/20261031190000_reconcile_lightek_mail_sending_policy"

class LightekMailPolicyUpgradeTest < ActiveSupport::TestCase
  setup do
    connection = ActiveRecord::Base.connection
    unless connection.data_source_exists?(:sending_policies)
      connection.create_table(:sending_policies) { |t| t.boolean :active, default: true }
    end
    @legacy = Class.new(ActiveRecord::Base) { self.table_name = "sending_policies" }
    @legacy.delete_all
    @policy = LightekMail::SendingPolicy.current
    @policy.update!(sending_enabled: false, stop_reason: nil)
  end

  def upgrade
    ActiveRecord::Migration.suppress_messages { ReconcileLightekMailSendingPolicy.new.up }
    @policy.reload
  end

  test "upgrade carries enabled legacy mail into the canonical singleton" do
    @legacy.create!(active: true)
    assert upgrade.sending_enabled?
    assert_nil @policy.stop_reason
    assert upgrade.sending_enabled?
    assert_equal 1, LightekMail::SendingPolicy.count
  end

  test "explicit canonical stop wins over enabled legacy configuration" do
    @legacy.create!(active: true)
    @policy.update!(stop_reason: "Operator stop")
    refute upgrade.sending_enabled?
    assert_equal "Operator stop", @policy.stop_reason
  end

  test "legacy pause stays paused and enabled canonical configuration stays enabled" do
    @legacy.create!(active: false)
    refute upgrade.sending_enabled?
    assert_equal "Preserved legacy mail sending pause", @policy.stop_reason
    @policy.update!(sending_enabled: true, stop_reason: nil)
    assert upgrade.sending_enabled?
  end

  test "fresh installation without a legacy row or previous delivery stays paused" do
    LightekMail::Message.where(direction: "outbound", state: "sent").delete_all
    refute upgrade.sending_enabled?
  end

  test "observed working sending without a legacy row survives upgrade" do
    user = User.create!(first_name: "Upgrade", last_name: "Mail", role: "super_admin", email_address: "upgrade-#{SecureRandom.hex(5)}@example.test", password: "Mail-test-2026-password!")
    domain = LightekMail::Domain.create!(user: user, name: "upgrade-#{SecureRandom.hex(5)}.test", verified_at: Time.current)
    account = LightekMail::Account.create!(user: user, domain: domain, address: "hello@#{domain.name}", display_name: "Upgrade", enabled: true)
    account.messages.create!(direction: "outbound", state: "sent", from_address: account.address, to_addresses: ["recipient@example.test"], subject: "Already sent", message_id: SecureRandom.uuid)
    assert upgrade.sending_enabled?
    @policy.update!(sending_enabled: false, stop_reason: "Abuse stop")
    refute upgrade.sending_enabled?
  end
end
