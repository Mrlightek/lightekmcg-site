require 'test_helper'

class NevaehOs::ExecutiveBriefTest < ActiveSupport::TestCase
  setup do
    @owner = create_user('super_admin')
    @client = create_user('client')
  end

  test 'the brief is restricted to platform super admins' do
    assert_raises(CanCan::AccessDenied) { NevaehOs::ExecutiveBrief.new(@client) }
    assert_raises(CanCan::AccessDenied) { NevaehOs::ExecutiveBrief.new(nil) }
  end

  test 'the brief shows real decisions and isolates goals and commercial records' do
    waiting = ProvisioningRequest.create!(owner: @client, execution_status: 'awaiting_approval')
    ProvisioningRequest.create!(owner: @owner, execution_status: 'draft')
    own_goal = create_goal(@owner, 'Review launch', 'blocked')
    create_goal(@client, 'Client goal', 'blocked')
    create_goal(@owner, 'Work in progress', 'running')
    owned = create_site(@owner)
    foreign = create_site(@client)
    order = create_order(owned)
    create_order(foreign)
    create_order(owned, status: 'fulfilled')
    create_order(owned).update!(deleted_at: Time.current)
    create_order(owned).update!(paid_at: nil)

    brief = NevaehOs::ExecutiveBrief.new(@owner).reply
    assert_match(/Start with Provisioning request ##{waiting.id}/, brief.fetch('text'))
    sections = brief.fetch('executive_brief').index_by { |section| section.fetch(:label) }
    approvals = sections.fetch('Provisioning decisions pending')
    assert_equal 1, approvals.fetch(:count)
    assert_equal Rails.application.routes.url_helpers.dashboard_provisioning_request_path(waiting),
      approvals.fetch(:rows).first.fetch(:path)
    assert_equal ["Goal ##{own_goal.id}: Review launch"],
      sections.fetch('Blocked Nevaeh goals').fetch(:rows).pluck(:title)
    assert_equal ["Order ##{order.id}"],
      sections.fetch('Paid orders awaiting fulfillment').fetch(:rows).pluck(:title)
  end

  test 'plain English and the command resolve to the executive brief' do
    assert_equal({'kind' => 'executive_brief'}, NevaehOs::Command.parse('/ceo'))
    assert_equal({'kind' => 'executive_brief'}, NevaehOs::Command.parse('Give me my CEO brief.'))
    assert_equal({'kind' => 'briefing'}, NevaehOs::Command.parse('/briefing'))
  end

  test 'agenda actions record the appointment and report conflicts without exposing notes' do
    attributes = {'category' => 'meeting', 'title' => 'Studio review',
      'starts_at' => '2026-11-30T14:00-05:00', 'ends_at' => '2026-11-30T14:30-05:00'}
    assert_raises(ArgumentError) { NevaehOs::AgendaActions.authorize!(@client, attributes) }
    assert_raises(ArgumentError) { NevaehOs::AgendaActions.authorize!(@owner, attributes.merge('starts_at' => '2026-02-31T14:00')) }
    assert_raises(ArgumentError) { NevaehOs::AgendaActions.authorize!(@owner, attributes.merge('ends_at' => attributes['starts_at'])) }

    item = NevaehOs::AgendaActions.authorize!(@owner, attributes)
    result = NevaehOs::AgendaActions.perform!(item)
    assert_equal @owner, NevaehAgendaItem.find(result.fetch('agenda_item_id')).user
    assert_equal 0, result.fetch('overlap_count')
    second = NevaehOs::AgendaActions.authorize!(@owner, attributes.merge('title' => 'Partner review'))
    assert_equal 1, NevaehOs::AgendaActions.perform!(second).fetch('overlap_count')

    travel_to Time.zone.parse('2026-11-27 10:00') do
      item.update!(notes: 'Confidential notes')
      NevaehAgendaItem.create!(user: @client, category: 'personal', title: 'Other account appointment',
        starts_at: item.starts_at, ends_at: item.ends_at)
      response = NevaehOs::ExecutiveBrief.new(@owner).agenda_reply.fetch('text')
      assert_includes response, 'Studio review'
      refute_includes response, 'Confidential notes'
      refute_includes response, 'Other account appointment'
    end
  end

  test 'chat recognizes reading and adding executive agenda entries' do
    assert_equal({'kind' => 'executive_brief', 'view' => 'agenda'}, NevaehOs::Command.parse('What is on my CEO agenda?'))
    command = NevaehOs::Command.parse('Add a meeting called "Launch review" to my CEO agenda from 2026-11-30T14:00 to 2026-11-30T14:30')
    assert_equal 'executive.agenda.create', command.fetch('intent')
    assert_equal 'Launch review', command.fetch('payload').fetch('title')
  end

  private

  def create_user(role)
    User.create!(first_name: 'Executive', last_name: 'Brief', role: role,
      email_address: "ceo-desk-#{SecureRandom.hex(6)}@example.test", password: 'Ceo-desk-test-password-2026!')
  end

  def create_goal(user, title, status)
    NevaehGoal.create!(user: user, title: title, status: status,
      request_key: SecureRandom.hex(12), fingerprint: SecureRandom.hex(32))
  end

  def create_site(owner)
    DymondSite::Site.create!(tenant: owner, name: 'Executive test',
      host: "ceo-desk-#{SecureRandom.hex(6)}.example.test")
  end

  def create_order(site, status: 'paid')
    LightekCommerce::Order.create!(site: site, customer_email: @client.email_address,
      status: status, paid_at: Time.current)
  end
end
