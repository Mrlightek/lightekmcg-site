require 'test_helper'

class NevaehOs::ExecutiveOperationsTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(first_name: 'Executive', last_name: 'Test', role: 'super_admin',
      email_address: "executive-#{SecureRandom.hex(8)}@example.test", password: 'Executive-operations-password!')
  end

  test 'calendar updates and cancellations keep the event UID and omit private notes' do
    starts = Time.zone.parse('2026-12-01T14:00')
    agenda = NevaehAgendaItem.create!(user: @owner, category: 'meeting', title: "Review\nTest", starts_at: starts,
      ends_at: starts + 30.minutes, notes: 'Private notes.')
    args = {item: agenda, organizer: 'ceo@example.test', attendee: 'guest@example.test'}
    request = NevaehOs::ExecutiveCalendar.attachment(**args)
    cancel = NevaehOs::ExecutiveCalendar.attachment(**args, sequence: 1, cancel: true)
    assert_equal request.lines.grep(/^UID:/), cancel.lines.grep(/^UID:/)
    assert_includes request, "METHOD:REQUEST\r\n"
    assert_includes cancel, "METHOD:CANCEL\r\n"
    assert_includes cancel, "SEQUENCE:1\r\n"
    refute_includes request, 'Private notes.'
    assert_includes request, 'SUMMARY:Review\\nTest'
  end

  test 'due work produces one Dashboard notification across sweeps' do
    item = NevaehExecutiveCase.create!(owner: @owner, title: 'Confirm the handoff', kind: 'follow_up', due_at: 1.minute.ago)
    2.times { ExecutiveFollowThroughJob.perform_now }
    assert item.reload.reminded_at?
    assert_equal 1, DymondDash::Notification.where(recipient: @owner, subject: item, title: 'Executive follow-up due').count
  end

  test 'phone intake only accepts signed events and replays an existing case' do
    route = NevaehExecutivePhoneRoute.create!(owner: @owner, key: SecureRandom.hex(24))
    body = {event_id: 'call-1', kind: 'voicemail', caller: '+12125550100', summary: 'Call back', urgent: true}.to_json
    timestamp = Time.current.to_i.to_s
    secret = SecureRandom.hex(32)
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")
    params = {key: route.key, timestamp: timestamp, signature: signature, body: body}
    LightekVault::Service.stub(:checkout!, ->(**) { {'signing_key'=>secret.dup} }) do
      assert_raises(NevaehOs::PhoneIntake::Denied) { NevaehOs::PhoneIntake.receive!(**params.merge(signature: '0' * 64)) }
      first = NevaehOs::PhoneIntake.receive!(**params)
      assert_equal first.id, NevaehOs::PhoneIntake.receive!(**params).id
      assert_equal 'call', first.kind
      assert_equal @owner.id, first.owner_id
      assert_includes first.details, 'Call back'
    end
  end
end
