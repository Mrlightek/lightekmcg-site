# frozen_string_literal: true

require 'minitest/autorun'
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

ActiveRecord::Schema.define { create_table(:users) { |table| table.string :full_name } }
require File.join(ROOT, 'db/migrate/20261122196000_add_shared_workspace')
require File.join(ROOT, 'db/migrate/20261123091000_add_shared_event_series')
AddSharedWorkspace.new.migrate(:up)
AddSharedEventSeries.new.migrate(:up)

class User < ApplicationRecord; end
module LightekPeople
  module Access
    class Denied < StandardError; end
  end
end
module LightekTeam
  class Workspace
    def self.employers_for(_actor) = User.where(full_name: 'Organizer')
    def initialize(actor:, employer:); end
    def roster = User.all
  end
end
module DymondDash
  class ApplicationController < ActionController::Base
    self.allow_forgery_protection = false
    def current_user = User.find(request.headers['X-Test-User'])
  end
end
module Dashboard; end

%w[models/lightek_workspace/calendar models/lightek_workspace/event models/lightek_workspace/event_guest
   controllers/dashboard/shared_workspace_controller controllers/dashboard/shared_calendars_controller].each do |path|
  require File.join(ROOT, 'app', path)
end

class SharedCalendarSeriesChecks < ActionController::TestCase
  tests Dashboard::SharedCalendarsController

  def setup
    Time.zone = 'Eastern Time (US & Canada)'
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { instance_eval(File.read(File.join(ROOT, 'config/routes/executive_operations.rb'))) }
    @controller.extend(@routes.url_helpers)
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

  private

  def location = {id: @calendar.id, employer_id: @organizer.id}
  def attributes
    {title: 'Operations review', starts_at: '2026-03-01T09:00', ends_at: '2026-03-01T10:00',
     repeat_frequency: 'weekly', repeat_count: '3', guest_ids: [@guest.id]}
  end
end
