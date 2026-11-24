# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'active_support/testing/time_helpers'
require 'active_record'
require 'active_support/all'
require 'action_controller'
require 'action_controller/test_case'
require 'action_mailer'
require 'active_job'

ROOT = File.expand_path('../..', __dir__)
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Base.time_zone_aware_attributes = true
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

ActiveRecord::ConnectionAdapters::TableDefinition.alias_method(:jsonb, :json)
ActiveRecord::Schema.define do
  create_table(:lightek_mail_accounts) do |table|
    table.references :user
    table.references :domain
    table.string :address
    table.boolean :enabled, default: true
  end
  create_table(:lightek_mail_messages) { |table| table.string :state; table.string :error_message }
  create_table(:lightek_mail_domains) { |table| table.string :name }
  create_table(:users) { |table| table.string :full_name; table.string :role; table.boolean :offboarded, default: false }
  create_table(:dymond_site_sites) { |table| table.string :name; table.references :tenant, polymorphic: true }
  create_table(:lightek_reservation_resources) do |table|
    table.references :site
    table.string :name
    table.string :kind
    table.integer :capacity
    table.integer :duration_minutes
    table.integer :notice_minutes
    table.boolean :published
    table.string :timezone
  end
  create_table(:lightek_reservations) do |table|
    table.references :resource
    table.references :customer
    table.datetime :starts_at
    table.datetime :ends_at
  end
end
%w[20261109000000_create_lightek_session_rooms 20261109003000_add_session_presentation
   20261112150000_add_direct_production_rooms].each { |name| require File.join(ROOT, 'db/migrate', name) }
CreateLightekSessionRooms.new.migrate(:up)
AddSessionPresentation.new.migrate(:up)
AddDirectProductionRooms.new.migrate(:up)
require File.join(ROOT, 'db/migrate/20261122196000_add_shared_workspace')
require File.join(ROOT, 'db/migrate/20261123091000_add_shared_event_series')
AddSharedWorkspace.new.migrate(:up)
AddSharedEventSeries.new.migrate(:up)
require File.join(ROOT, 'db/migrate/20261123092000_link_rooms_to_shared_calendar_events')
LinkRoomsToSharedCalendarEvents.new.migrate(:up)
require File.join(ROOT, 'db/migrate/20261123101000_create_shared_calendar_external_invitations')
CreateSharedCalendarExternalInvitations.new.migrate(:up)

class ApplicationJob < ActiveJob::Base; end
ActiveJob::Base.queue_adapter = :test

module LightekMail
  class Account < ApplicationRecord
    self.table_name = 'lightek_mail_accounts'
    belongs_to :user
    belongs_to :domain, optional: true
    scope :mailboxes, -> { all }
    def sending_ready? = enabled?
    def display_name = 'Organizer'
  end
  class Domain < ApplicationRecord
    self.table_name = 'lightek_mail_domains'
  end
  class Message < ApplicationRecord
    self.table_name = 'lightek_mail_messages'
  end
  module Access
    class Denied < StandardError; end
    def self.accounts(_actor) = Account.all
    def self.authorize!(_actor); end
  end
  module Conversation
    def self.references(_account, _record) = []
  end
  module Transport
    def self.settings = {}
  end
end

class User < ApplicationRecord; end
module LightekPeople
  module Access
    class Denied < StandardError; end
  end
end
module LightekTeam
  class Workspace
    def self.employers_for(actor) = actor.offboarded? ? User.none : User.where(full_name: 'Organizer')

    def initialize(actor:, employer:); end
    def roster = User.where(offboarded: false)
  end
end
module DymondDash
  class ApplicationController < ActionController::Base
    self.allow_forgery_protection = false
    helper_method :current_user
    def current_user = User.find(request.headers['X-Test-User'])
  end
end
module Dashboard; end
module DymondSite
  class Site < ApplicationRecord
    self.table_name = 'dymond_site_sites'
    belongs_to :tenant, polymorphic: true
  end
end
module LightekReservations
  class Resource < ApplicationRecord
    self.table_name = 'lightek_reservation_resources'
    belongs_to :site, class_name: 'DymondSite::Site'
    def native_session? = kind == 'video'
  end
  class Reservation < ApplicationRecord
    self.table_name = 'lightek_reservations'
  end
end
module LightekSettings
  module WebsiteIdentity
    def self.sites_for(actor) = DymondSite::Site.where(tenant: actor)
  end
end
module LightekSessions
  module Media
    def self.configured?(site) = site.name != 'Unconfigured'
  end
  class CloseRoomJob
    def self.enqueued = @enqueued ||= []
    def self.perform_later(id) = enqueued << id
  end
end

%w[models/lightek_workspace/calendar models/lightek_workspace/event models/lightek_workspace/event_guest
   models/lightek_sessions/room models/lightek_sessions/member services/lightek_sessions/access
   services/lightek_sessions/room_creation services/lightek_sessions/presentation services/lightek_sales/task_calendar
   services/lightek_mail/submission services/lightek_mail/sending_limits
   models/lightek_workspace/external_invitation services/lightek_workspace/calendar_invitation_mail
   jobs/lightek_workspace/external_invitation_job mailers/lightek_mail/message_mailer
   controllers/dashboard/shared_workspace_controller controllers/dashboard/shared_calendars_controller].each do |path|
  require File.join(ROOT, 'app', path)
end

class SharedCalendarSeriesChecks < ActionController::TestCase
  tests Dashboard::SharedCalendarsController
  include ActiveSupport::Testing::TimeHelpers

  def setup
    Time.zone = 'Eastern Time (US & Canada)'
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      instance_eval(File.read(File.join(ROOT, 'config/routes/executive_operations.rb')))
      get '/sessions/:key', to: 'session_rooms#show', as: :session_room
    end
    LightekSessions::CloseRoomJob.enqueued.clear
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    @controller.extend(@routes.url_helpers)
    Dashboard::SharedCalendarsController.prepend_view_path(File.join(ROOT, 'app/views'))
    Dashboard::SharedCalendarsController.helper_method(:dashboard_shared_calendar_path, :dashboard_shared_calendars_path,
      :schedule_dashboard_shared_calendar_path, :event_ics_dashboard_shared_calendar_path, :session_room_path,
      :add_meeting_dashboard_shared_calendar_path, :respond_dashboard_shared_calendar_path,
      :reschedule_dashboard_shared_calendar_path, :cancel_event_dashboard_shared_calendar_path,
      :invite_external_dashboard_shared_calendar_path, :retry_external_invitation_dashboard_shared_calendar_path)
    Dashboard::SharedCalendarsController.helper { def l(value, **) = value.to_s }
    @organizer = User.create!(full_name: 'Organizer')
    @guest = User.create!(full_name: 'Guest')
    @calendar = LightekWorkspace::Calendar.create!(employer: @organizer, name: 'Operations')
    @request.set_header('HTTP_X_TEST_USER', @organizer.id.to_s)
  end

  def test_series_preserves_local_hour_and_guest_assignments_across_daylight_saving
    post :schedule, params: location.merge(event: attributes)
    assert_response :see_other
    events = @calendar.events.order(:starts_at)
    assert_equal [9, 9, 9], events.map { |event| event.starts_at.in_time_zone.hour }
    assert_equal [14, 13, 13], events.map { |event| event.starts_at.utc.hour }
    assert_equal 1, events.map(&:series_key).uniq.length
    assert_equal [[@guest.id], [@guest.id], [@guest.id]], events.map { |event| event.guests.pluck(:user_id) }
  end

  def test_cancel_following_preserves_earlier_occurrences
    post :schedule, params: location.merge(event: attributes)
    pivot = @calendar.events.order(:starts_at).second
    post :cancel, params: location.merge(event_id: pivot.id, scope: 'following')
    assert_response :see_other
    assert_equal 1, @calendar.events.scheduled.count
    assert_equal 2, @calendar.events.where.not(cancelled_at: nil).count
  end

  def test_invalid_series_leaves_no_events
    post :schedule, params: location.merge(event: attributes.merge(repeat_count: '53'))
    assert_response :see_other
    assert_empty @calendar.events
  end

  def test_creating_a_meeting_is_idempotent_and_admission_remains_room_controlled
    travel_to(Time.zone.local(2026, 2, 27, 9)) do
      event = schedule_meeting
      room = event.session_room
      assert_equal event.starts_at, room.starts_at
      assert_equal event.ends_at, room.ends_at
      refute room.resource.published?
      assert_equal 'waiting', room.members.find_by!(user: @guest).status
      assert LightekSessions::Access.authorize!(room, @guest)
      assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.authorize!(room, @guest, now: event.starts_at, joining: true) }
      room.update!(status: 'open')
      room.members.find_by!(user: @guest).update!(status: 'admitted')
      assert LightekSessions::Access.authorize!(room, @guest, now: event.starts_at, joining: true)

      post :add_meeting, params: location.merge(event_id: event.id, site_id: room.resource.site_id)
      assert_response :see_other
      assert_equal room.id, event.reload.session_room_id

      outsider = User.create!(full_name: 'Uninvited teammate')
      assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.authorize!(room, outsider) }
      @guest.update!(offboarded: true)
      assert_raises(LightekSessions::Access::Denied) { LightekSessions::Access.authorize!(room, @guest) }
    end
  end

  def test_reschedule_keeps_room_key_and_cancel_ends_room
    travel_to(Time.zone.local(2026, 2, 27, 9)) do
      event = schedule_meeting
      room = event.session_room
      patch :reschedule, params: location.merge(event_id: event.id,
        event: {starts_at: '2026-03-01T10:00', ends_at: '2026-03-01T10:30'})
      assert_response :see_other
      assert_equal room.key, event.reload.session_room.key
      assert_equal event.starts_at, room.reload.starts_at
      assert_equal 30, room.resource.duration_minutes

      room.update!(status: 'open')
      post :cancel, params: location.merge(event_id: event.id)
      assert_response :see_other
      assert event.reload.cancelled_at?
      assert_equal 'ended', room.reload.status
      assert_equal [room.id], LightekSessions::CloseRoomJob.enqueued
    end
  end

  def test_meeting_link_is_exported_only_for_invited_users
    travel_to(Time.zone.local(2026, 2, 27, 9)) do
      event = schedule_meeting
      @request.set_header('HTTP_X_TEST_USER', @guest.id.to_s)
      get :ics, params: location.merge(event_id: event.id)
      assert_response :success
      assert_includes response.body.gsub(/\r\n[ \t]/, ""), "/sessions/#{event.session_room.key}"

      outsider = User.create!(full_name: 'Uninvited teammate')
      @request.set_header('HTTP_X_TEST_USER', outsider.id.to_s)
      get :ics, params: location.merge(event_id: event.id)
      assert_response :success
      refute_includes response.body, '/sessions/'
    end
  end

  def test_calendar_renders_meeting_button_for_organizer_and_link_for_invited_guest
    travel_to(Time.zone.local(2026, 2, 27, 9)) do
      post :schedule, params: location.merge(event: attributes.except(:repeat_frequency, :repeat_count))
      event = @calendar.events.last
      site = DymondSite::Site.create!(name: 'Production website', tenant: @organizer)
      get :show, params: location.merge(date: event.starts_at.to_date.to_s)
      assert_response :success
      assert_includes response.body, 'Add video meeting'

      post :add_meeting, params: location.merge(event_id: event.id, site_id: site.id)
      @request.set_header('HTTP_X_TEST_USER', @guest.id.to_s)
      get :show, params: location.merge(date: event.starts_at.to_date.to_s)
      assert_response :success
      assert_includes response.body, 'Open video meeting'
      assert_includes response.body, "/sessions/#{event.reload.session_room.key}"
      refute_includes response.body, 'Add video meeting'
    end
  end

  def test_guest_cannot_create_a_meeting_and_unconfigured_site_creates_no_room
    travel_to(Time.zone.local(2026, 2, 27, 9)) do
      post :schedule, params: location.merge(event: attributes.except(:repeat_frequency, :repeat_count))
      event = @calendar.events.last
      site = DymondSite::Site.create!(name: 'Unconfigured', tenant: @organizer)
      @request.set_header('HTTP_X_TEST_USER', @guest.id.to_s)
      post :add_meeting, params: location.merge(event_id: event.id, site_id: site.id)
      assert_response :forbidden

      @request.set_header('HTTP_X_TEST_USER', @organizer.id.to_s)
      post :add_meeting, params: location.merge(event_id: event.id, site_id: site.id)
      assert_response :see_other
      assert_nil event.reload.session_room_id
    end
  end

  def test_external_invitation_is_private_and_follows_edits_and_cancellation
    travel_to(Time.zone.local(2026, 2, 27, 9)) do
      event = schedule_meeting
      mailbox = LightekMail::Account.create!(user: @organizer, address: 'organizer@example.com')
      other_mailbox = LightekMail::Account.create!(user: @guest, address: 'other@example.com')
      request_parameters = location.merge(event_id: event.id, attendee_address: 'outside@example.net')
      @request.set_header('HTTP_X_TEST_USER', @guest.id.to_s)
      post :invite_external, params: request_parameters.merge(mailbox_id: other_mailbox.id)
      assert_response :forbidden

      @request.set_header('HTTP_X_TEST_USER', @organizer.id.to_s)
      post :invite_external, params: request_parameters.merge(mailbox_id: other_mailbox.id)
      assert_response :see_other
      assert_empty event.external_invitations
      post :invite_external, params: request_parameters.merge(mailbox_id: mailbox.id)
      assert_response :see_other
      assert_equal 1, event.external_invitations.count
      invitation = event.external_invitations.first
      assert_equal [invitation.id, 0], ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]

      post :invite_external, params: request_parameters.merge(mailbox_id: mailbox.id)
      assert_equal 1, event.external_invitations.count

      get :show, params: location.merge(date: event.starts_at.to_date.to_s)
      assert_includes response.body, 'outside@example.net'
      assert_includes response.body, 'Send invitation'
      refute_includes response.body, 'other@example.com'

      @request.set_header('HTTP_X_TEST_USER', @guest.id.to_s)
      get :show, params: location.merge(date: event.starts_at.to_date.to_s)
      refute_includes response.body, 'outside@example.net'
      refute_includes response.body, 'Send invitation'
      @request.set_header('HTTP_X_TEST_USER', @organizer.id.to_s)

      initial = capture_calendar_delivery(invitation, 0)
      assert_includes initial, 'METHOD:REQUEST'
      assert_includes initial, 'SEQUENCE:0'
      assert_includes initial, "UID:#{invitation.uid}"
      refute_includes initial, event.session_room.key

      patch :reschedule, params: location.merge(event_id: event.id, event: {title: 'Planning review'})
      assert_response :see_other
      assert_equal 1, invitation.reload.sequence
      assert_equal [invitation.id, 1], ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]
      assert_nil capture_calendar_delivery(invitation, 0)
      update = capture_calendar_delivery(invitation, 1)
      assert_includes update, "UID:#{invitation.uid}"
      assert_includes update, 'SEQUENCE:1'
      assert_includes update, 'SUMMARY:Planning review'

      post :cancel, params: location.merge(event_id: event.id)
      assert_response :see_other
      assert_equal 2, invitation.reload.sequence
      cancellation = capture_calendar_delivery(invitation, 2)
      assert_includes cancellation, 'METHOD:CANCEL'
      assert_includes cancellation, "UID:#{invitation.uid}"
      assert_includes cancellation, 'STATUS:CANCELLED'
      get :show, params: location.merge(date: event.starts_at.to_date.to_s)
      assert_includes response.body, 'Cancelled events with external guests'

      invitation.reload.message.update!(state: 'failed', error_message: 'Sender unavailable.')
      get :show, params: location.merge(date: event.starts_at.to_date.to_s)
      assert_includes response.body, 'Retry delivery'
      post :retry_external_invitation, params: location.merge(event_id: event.id, invitation_id: invitation.id)
      assert_response :see_other
      assert_equal 3, invitation.reload.sequence
      assert_equal [invitation.id, 3], ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]
      assert_includes capture_calendar_delivery(invitation, 3), 'METHOD:CANCEL'
    end
  end

  def test_matching_current_calendar_reply_updates_rsvp_once
    travel_to(Time.zone.local(2026, 2, 27, 9)) do
      event = schedule_meeting
      mailbox = LightekMail::Account.create!(user: @organizer, address: 'organizer@example.com')
      invitation = event.external_invitations.create!(mailbox: mailbox, sequence: 1, organizer_address: mailbox.address,
        attendee_address: 'guest@example.net', uid: "#{SecureRandom.uuid}@calendar.lightek")
      envelope = Struct.new(:recipients).new([mailbox.address])
      reply = lambda do |sender: invitation.attendee_address, sequence: 1, uid: invitation.uid,
                        status: 'ACCEPTED', stamp: '20260227T135900Z'|
        data = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'METHOD:REPLY', 'BEGIN:VEVENT', "UID:#{uid}",
          "DTSTAMP:#{stamp}", "SEQUENCE:#{sequence}", "ORGANIZER:mailto:#{mailbox.address}",
          "ATTENDEE;CN=\"Guest: External\";PARTSTAT=#{status}:mailto:#{invitation.attendee_address}",
          'END:VEVENT', 'END:VCALENDAR'].join("\r\n")
        message = Mail.new(from: sender, to: mailbox.address, body: 'Calendar reply')
        message.part(content_type: 'text/calendar; method=REPLY; charset=UTF-8', body: data)
        LightekWorkspace::CalendarInvitationMail.record_reply(account: mailbox, envelope: envelope, mail: Mail.new(message.encoded))
      end
      refute reply.call(sender: 'other@example.net')
      refute reply.call(sequence: 0)
      refute reply.call(sequence: "0\r\nSEQUENCE:1")
      refute reply.call(uid: "#{SecureRandom.uuid}@calendar.lightek")
      assert_equal 'pending', invitation.reload.response
      assert reply.call
      assert_equal 'accepted', invitation.reload.response
      refute reply.call(status: 'DECLINED', stamp: '20260227T135800Z')
      assert reply.call(status: 'TENTATIVE', stamp: '20260227T140000Z')
      assert_equal 'tentative', invitation.reload.response
      post :cancel, params: location.merge(event_id: event.id)
      refute reply.call(sequence: 2, stamp: '20260227T140100Z')
    end
  end

  private

  def capture_calendar_delivery(invitation, sequence)
    capture = nil
    submission = lambda do |account:, attributes:, idempotency_key:, uploads:|
      file = uploads.fetch(0)
      capture = file.fetch(:io).string
      attachment = Struct.new(:filename, :content_type, :download).new(file.fetch(:filename), file.fetch(:content_type), capture)
      record = Struct.new(:attachments, :idempotency_key, :message_id, :in_reply_to, :account, :from_address, :to_addresses,
        :cc_addresses, :bcc_addresses, :subject, :text_body, :html_body).new([attachment], idempotency_key, 'test@example.com',
        nil, account, account.address, attributes[:to], [], [], attributes[:subject], attributes[:text], nil)
      wire = Mail.new(LightekMail::MessageMailer.outbound(record).message.encoded)
      assert_equal 'multipart/alternative', wire.mime_type
      assert_equal attributes[:text].gsub("\n", "\r\n"), wire.text_part.decoded
      calendar = wire.parts.find { |part| part.mime_type == 'text/calendar' }
      assert_equal capture[/^METHOD:(REQUEST|CANCEL)\r?$/, 1], calendar.content_type_parameters.fetch('method')
      assert_equal capture.gsub("\r\n", "\n"), calendar.decoded.gsub("\r\n", "\n")
      LightekMail::Message.create!(state: 'queued')
    end
    LightekMail::Submission.stub(:create!, submission) do
      LightekWorkspace::ExternalInvitationJob.perform_now(invitation.id, sequence)
    end
    capture
  end

  def schedule_meeting
    post :schedule, params: location.merge(event: attributes.except(:repeat_frequency, :repeat_count))
    assert_response :see_other
    event = @calendar.events.last
    site = DymondSite::Site.create!(name: 'Production website', tenant: @organizer)
    post :add_meeting, params: location.merge(event_id: event.id, site_id: site.id)
    assert_response :see_other
    event.reload
  end

  def location = {id: @calendar.id, employer_id: @organizer.id}
  def attributes
    {title: 'Operations review', starts_at: '2026-03-01T09:00', ends_at: '2026-03-01T10:00',
     repeat_frequency: 'weekly', repeat_count: '3', guest_ids: [@guest.id]}
  end
end
