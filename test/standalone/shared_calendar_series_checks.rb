# frozen_string_literal: true

require 'minitest/autorun'
require 'active_support/testing/time_helpers'
require 'active_record'
require 'active_support/all'
require 'action_controller'
require 'action_controller/test_case'

ROOT = File.expand_path('../..', __dir__)
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Base.time_zone_aware_attributes = true
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

ActiveRecord::ConnectionAdapters::TableDefinition.alias_method(:jsonb, :json)
ActiveRecord::Schema.define do
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
    @controller.extend(@routes.url_helpers)
    Dashboard::SharedCalendarsController.prepend_view_path(File.join(ROOT, 'app/views'))
    Dashboard::SharedCalendarsController.helper_method(:dashboard_shared_calendar_path, :dashboard_shared_calendars_path,
      :schedule_dashboard_shared_calendar_path, :event_ics_dashboard_shared_calendar_path, :session_room_path,
      :add_meeting_dashboard_shared_calendar_path, :respond_dashboard_shared_calendar_path,
      :reschedule_dashboard_shared_calendar_path, :cancel_event_dashboard_shared_calendar_path)
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

  private

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
