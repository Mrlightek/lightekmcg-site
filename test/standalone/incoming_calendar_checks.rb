require "minitest/autorun"
require "minitest/mock"
require "active_record"
require "active_support/all"
require "action_controller"
require "action_controller/test_case"
require "mail"

ROOT = File.expand_path("../..", __dir__)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::ConnectionAdapters::TableDefinition.alias_method(:jsonb, :json)
ActiveRecord::Schema.define do
  create_table(:lightek_mail_accounts) { |t| t.string :address; t.integer :user_id }
  create_table(:lightek_mail_messages) do |t|
    t.references :account
    t.string :message_id, :state, :direction, :subject, :error_message
    t.boolean :junk, :trashed, :starred, :archived, default: false
    t.string :spam_reason
    t.datetime :read_at
  end
  create_table(:lightek_mail_sending_policies)
end

require File.join(ROOT, "db/migrate/20261123102000_store_incoming_calendar_invitations")
StoreIncomingCalendarInvitations.new.migrate(:up)

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

module LightekMail
  class Account < ApplicationRecord
    self.table_name = "lightek_mail_accounts"
    has_many :messages, class_name: "LightekMail::Message"
    def display_name = address
  end
  class Message < ApplicationRecord
    self.table_name = "lightek_mail_messages"
    belongs_to :account
  end
  module Conversation
    LIMIT = 30
    def self.messages(*) = []
  end
  class MessageContent
    def initialize(_); end
  end
  module Access
    class Denied < StandardError; end
    def self.authorize!(_); end
    def self.accounts(_actor) = Account.all
  end
end

module Dashboard; end
module DymondDash
  class ApplicationController < ActionController::Base
    self.allow_forgery_protection = false
    def current_user = Struct.new(:id).new(request.headers["X-Test-User"].to_i)
  end
end

%w[models/lightek_mail/calendar_invitation models/lightek_mail/sending_policy services/lightek_mail/submission
   services/lightek_mail/spam_scanner services/lightek_mail/calendar_notice services/lightek_mail/incoming_calendar
   controllers/dashboard/mail_studio_controller].each { |path| require File.join(ROOT, "app", path) }

class IncomingCalendarChecks < ActionController::TestCase
  tests Dashboard::MailStudioController
  ENVELOPE = Struct.new(:recipients)

  def setup
    Time.zone = "America/New_York"
    @account = LightekMail::Account.create!(user_id: 12, address: "owner@example.net")
    @request.set_header("HTTP_X_TEST_USER", "12")
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get "/mail", to: "dashboard/mail_studio#index", as: :dashboard_mail
      get "/mail/:account_id/compose", to: "dashboard/mail_studio#compose", as: :compose_dashboard_mail
      patch "/mail/:account_id/messages/:id/flag", to: "dashboard/mail_studio#flag_message", as: :flag_dashboard_mail_message
      get "/mail/:account_id/calendar", to: "dashboard/mail_studio#calendar", as: :calendar_dashboard_mail
      get "/mail/:account_id/messages/:id", to: "dashboard/mail_studio#show_message", as: :dashboard_mail_message
      post "/mail/:account_id/messages/:id/calendar", to: "dashboard/mail_studio#respond_to_calendar", as: :respond_to_dashboard_mail_calendar
    end
    @controller.extend(@routes.url_helpers)
    Dashboard::MailStudioController.prepend_view_path(File.join(ROOT, "app/views"))
    Dashboard::MailStudioController.helper_method(:dashboard_mail_path, :dashboard_mail_message_path,
      :calendar_dashboard_mail_path, :respond_to_dashboard_mail_calendar_path, :compose_dashboard_mail_path,
      :flag_dashboard_mail_message_path)
  end

  def test_acceptance_queues_one_reply_and_renders_the_mail_calendar
    message = receive
    assert_equal "pending", current.response
    assert_equal Time.utc(2026, 12, 4, 15), current.starts_at
    assert_equal Time.utc(2026, 12, 4, 15, 30), current.ends_at

    get :show_message, params: {account_id: @account.id, id: message.id, workspace: "1"}
    assert_response :success
    assert_includes response.body, 'value="accepted"'
    assert_includes response.body, 'value="tentative"'
    assert_includes response.body, 'value="declined"'

    sends = []
    submission = lambda do |account:, attributes:, idempotency_key:, uploads:|
      sends << idempotency_key
      assert_equal @account, account
      assert_equal ["planner@example.org"], attributes.fetch(:to)
      upload = uploads.fetch(0)
      mime = Mail.new
      mime.attachments[upload.fetch(:filename)] = {mime_type: upload.fetch(:content_type), content: upload.fetch(:io).string}
      part = Mail.new(mime.encoded).attachments.first
      assert_equal "REPLY", part.content_type_parameters.fetch("method")
      calendar = Icalendar::Calendar.parse(part.decoded).first
      assert_equal "REPLY", calendar.ip_method.to_s
      assert_equal "workshop@example.org", calendar.events.first.uid.to_s
      assert_equal (sends.size - 1).to_s, calendar.events.first.sequence.to_s
      assert_equal ["ACCEPTED"], calendar.events.first.attendee.first.ical_params["partstat"]
      @account.messages.create!(direction: "outbound", state: "queued")
    end
    LightekMail::Submission.stub(:create!, submission) do
      2.times do
        post :respond_to_calendar, params: {account_id: @account.id, id: message.id, workspace: "1", choice: "accepted"}
        assert_response :see_other
        assert_includes response.location, "workspace=1"
      end
    end
    assert_equal 1, sends.size
    assert_equal "accepted", current.response

    get :calendar, params: {account_id: @account.id, date: "2026-12-01"}
    assert_response :success
    assert_includes response.body, "Workshop"
    assert_includes response.body, "Accepted"

    reply = current.reply_message
    assert LightekMail::IncomingCalendar.current_reply?(@account, reply)
    moved = receive(version: 1)
    assert_nil current.reply_message_id
    refute LightekMail::IncomingCalendar.current_reply?(@account, reply)
    LightekMail::Submission.stub(:create!, submission) do
      post :respond_to_calendar, params: {account_id: @account.id, id: moved.id, choice: "accepted"}
      assert_response :see_other
    end
    assert_equal 2, sends.uniq.size

    @request.set_header("HTTP_X_TEST_USER", "13")
    get :calendar, params: {account_id: @account.id, date: "2026-12-01"}
    assert_response :forbidden
    post :respond_to_calendar, params: {account_id: @account.id, id: message.id, choice: "declined"}
    assert_response :forbidden
  end

  def test_update_and_cancellation_follow_the_same_event_in_version_order
    initial = receive
    current.update!(response: "tentative")
    moved = receive(version: 2, title: "New workshop time")
    assert_equal initial.calendar_notice.fetch("uid"), current.uid
    assert_equal moved.id, current.source_message_id
    assert_equal "tentative", current.response
    old = receive(version: 1)
    assert_equal "New workshop time", current.title
    assert_raises(ArgumentError) { LightekMail::IncomingCalendar.review!(@account, old, choice: "accepted") }

    unverified = receive(method: "CANCEL", version: 3, signed: false)
    refute current.cancelled?
    assert_equal false, unverified.calendar_notice.fetch("trusted")
    post :respond_to_calendar, params: {account_id: @account.id, id: unverified.id, choice: "apply"}
    assert_response :see_other
    assert current.cancelled?

    receive(version: 2)
    assert current.cancelled?
    assert_equal 1, LightekMail::CalendarInvitation.for_mailbox(@account).count
    get :calendar, params: {account_id: @account.id, date: "2026-12-01"}
    refute_includes response.body, "New workshop time"
  end

  def test_direct_recipient_boundary_and_trusted_cancellation_before_request
    forwarded = receive(envelope_recipients: ["team@example.net"])
    assert_empty forwarded.calendar_notice
    wrong_attendee = receive(attendee: "other@example.net")
    assert_empty wrong_attendee.calendar_notice
    assert_nil current

    receive(method: "CANCEL", version: 4)
    assert current.cancelled?
    receive(version: 3)
    assert current.cancelled?
    assert_equal 4, current.sequence
  end

  def test_google_provider_and_all_day_notice_and_unsupported_series
    item = receive(sender: "calendar-notification@google.com", timing: "DTSTART;VALUE=DATE:20261204\r\nDTEND;VALUE=DATE:20261206")
    assert item.calendar_notice.fetch("trusted")
    assert current.all_day?
    assert_equal Time.utc(2026, 12, 4), current.starts_at
    assert_equal Time.utc(2026, 12, 6), current.ends_at
    series = receive(version: 1, timing: "DTSTART:20261204T150000Z\r\nRRULE:FREQ=WEEKLY")
    assert_empty series.calendar_notice
    assert_equal 0, current.sequence
  end

  def test_only_trusts_scanner_dkim_result_for_original_full_message
    outcome = {"action" => "no action", "score" => 0, "symbols" => {
      "R_DKIM_ALLOW" => {"options" => ["example.org:s=mail", "malformed"]}
    }}
    raw = "From: planner@example.org\r\nDKIM-Signature: v=1; d=example.org; s=mail\r\n\r\nHello"
    session = Object.new
    session.define_singleton_method(:request) do |request|
      raise "Raw message changed" unless request.body == raw
      Struct.new(:code, :body).new("200", outcome.to_json)
    end
    Net::HTTP.stub(:start, ->(*, **, &block) { block.call(session) }) do
      assert_equal ["example.org"], LightekMail::SpamScanner.scan!(Mail.new(raw), raw: raw).fetch("dkim_domains")
    end
    assert_empty LightekMail::SpamScanner.send(:dkim_domains, outcome, raw.sub("v=1;", "v=1; l=0;"))
    assert_empty LightekMail::SpamScanner.send(:dkim_domains, outcome, "From: other@example.org\r\n#{raw}")
  end

  private

  def current
    LightekMail::CalendarInvitation.for_mailbox(@account).first
  end

  def receive(method: "REQUEST", version: 0, title: "Workshop", signed: true, sender: "planner@example.org",
              attendee: @account.address, envelope_recipients: [@account.address],
              timing: "DTSTART;TZID=Eastern Standard Time:20261204T100000\r\nDURATION:PT30M")
    data = ["BEGIN:VCALENDAR", "VERSION:2.0", "METHOD:#{method}", "BEGIN:VEVENT", "UID:workshop@example.org",
      "DTSTAMP:20261101T170000Z", "ORGANIZER:mailto:planner@example.org", "SEQUENCE:#{version}",
      ("ATTENDEE;CN=\"Owner: Team\";RSVP=TRUE:mailto:#{attendee}" if method == "REQUEST"),
      (timing if method == "REQUEST"), "SUMMARY:#{title}", "END:VEVENT", "END:VCALENDAR"].compact.join("\r\n")
    mail = Mail.new(from: sender, to: @account.address, body: "Calendar request")
    mail.part(content_type: "text/calendar; method=#{method}; charset=UTF-8", body: data)
    message = @account.messages.create!(direction: "inbound", state: "inbox", message_id: "#{SecureRandom.uuid}@example.org")
    LightekMail::IncomingCalendar.receive!(message, mail: Mail.new(mail.encoded),
      envelope: ENVELOPE.new(envelope_recipients), scan: {"dkim_domains" => signed ? [sender.split("@").last] : []})
    message.reload
  end
end
