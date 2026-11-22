require 'test_helper'

class LightekTeam::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @employer = account('super_admin')
    @staff = account('employee')
    @outsider = account('client')
    @employment = LightekPeople::Employment.new(employer: @employer, worker: @staff, title: 'Producer',
      starts_on: Date.current, active: true)
    @employment.lifecycle_activation = true
    @employment.save!
    @workspace = LightekTeam::Workspace.new(actor: @employer, employer: @employer)
  end

  test 'private channels require a channel invitation and current employment' do
    channel = @workspace.create!('name' => 'Executive', 'private_channel' => true)
    staff = LightekTeam::Workspace.new(actor: @staff, employer: @employer)
    refute staff.channels.exists?(channel.id)
    assert_raises(ActiveRecord::RecordNotFound) { @workspace.change_member!(channel.id, @outsider.id, operation: :add) }

    @workspace.change_member!(channel.id, @staff.id, operation: :add)
    assert staff.channels.exists?(channel.id)
    assert_raises(LightekPeople::Access::Denied) { staff.change_member!(channel.id, @staff.id, operation: :remove) }

    @employment.update_columns(active: false)
    assert_raises(LightekPeople::Access::Denied) { staff.channels.load }
    assert_raises(LightekPeople::Access::Denied) { staff.post!(channel.id, message_attributes) }
    assert_raises(LightekPeople::Access::Denied) { LightekTeam::Workspace.new(actor: @outsider, employer: @employer) }
  end

  test 'company-wide channels support idempotent posts and same-channel replies' do
    channel = @workspace.create!('name' => 'production', 'private_channel' => false)
    other_channel = @workspace.create!('name' => 'operations', 'private_channel' => false)
    staff = LightekTeam::Workspace.new(actor: @staff, employer: @employer)
    assert staff.channels.exists?(channel.id)

    attributes = message_attributes
    root = staff.post!(channel.id, attributes)
    assert_equal root.id, staff.post!(channel.id, attributes).id
    assert_raises(ArgumentError) { staff.post!(channel.id, attributes.merge('body' => 'Changed')) }
    assert_equal 1, channel.messages.count

    reply = @workspace.post!(channel.id, message_attributes.merge('reply_to_id' => root.id))
    assert_equal root, reply.reply_to
    assert_raises(ActiveRecord::RecordNotFound) do
      @workspace.post!(other_channel.id, message_attributes.merge('reply_to_id' => root.id))
    end
  end

  test 'shared channels require acceptance and isolate both organizational rosters' do
    partner = account('white_label')
    guest = account('employee')
    employment = LightekPeople::Employment.new(employer: partner, worker: guest, title: 'Coordinator',
      starts_on: Date.current, active: true)
    employment.lifecycle_activation = true
    employment.save!
    partner_workspace = LightekTeam::Workspace.new(actor: partner, employer: partner)
    guest_workspace = LightekTeam::Workspace.new(actor: guest, employer: partner)
    host_sharing = LightekTeam::SharedChannels.new(workspace: @workspace, organization: @employer, actor: @employer)
    partner_sharing = LightekTeam::SharedChannels.new(workspace: partner_workspace, organization: partner, actor: partner)
    guest_sharing = LightekTeam::SharedChannels.new(workspace: guest_workspace, organization: partner, actor: guest)
    internal = @workspace.create!('name' => 'internal', 'private_channel' => false)
    shared = host_sharing.invite!('name' => 'screening-partners', 'partner_email' => partner.email_address)

    assert_includes partner_sharing.incoming, shared.partnership
    refute partner_workspace.channels.exists?(shared.id)
    assert_empty guest_sharing.incoming
    assert_raises(LightekPeople::Access::Denied) { guest_sharing.accept!(shared.partnership.id) }
    assert_raises(ActiveRecord::RecordNotFound) { host_sharing.accept!(shared.partnership.id) }

    assert_equal shared, partner_sharing.accept!(shared.partnership.id)
    assert_equal shared, partner_sharing.accept!(shared.partnership.id)
    assert_equal 1, shared.partnership.memberships.count
    assert partner_workspace.channels.exists?(shared.id)
    refute partner_workspace.channels.exists?(internal.id)
    refute guest_workspace.channels.exists?(shared.id)
    assert_raises(ActiveRecord::RecordNotFound) { partner_workspace.change_member!(shared.id, @staff.id, operation: :add) }
    assert_raises(ActiveRecord::RecordNotFound) { @workspace.change_member!(shared.id, guest.id, operation: :add) }
    partner_workspace.change_member!(shared.id, guest.id, operation: :add)
    assert_equal partner, guest_workspace.post!(shared.id, message_attributes).organization

    employment.update_columns(active: false)
    assert_raises(LightekPeople::Access::Denied) { guest_workspace.channels.load }
    partner_sharing.disconnect!(shared)
    refute partner_workspace.channels.exists?(shared.id)
    assert_raises(ActiveRecord::RecordNotFound) { partner_workspace.post!(shared.id, message_attributes) }
    assert @workspace.channels.exists?(shared.id)
    assert_equal 1, shared.messages.count
    assert_raises(ActiveRecord::RecordNotFound) { partner_sharing.accept!(shared.partnership.id) }
  end

  private

  def account(role)
    User.create!(first_name: 'Team', last_name: 'Test', role: role,
      email_address: "team-#{SecureRandom.hex(6)}@example.test", password: 'Team-chat-test-password-2026!')
  end

  def message_attributes
    {'body' => 'Production is ready for review.', 'request_key' => SecureRandom.uuid}
  end
end
