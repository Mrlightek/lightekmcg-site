# frozen_string_literal: true

require 'digest'
require 'stringio'
require 'uri'

module NevaehOs
  class ExecutiveDelivery
    def initialize(actor:, mailbox_id:)
      raise LightekPeople::Access::Denied unless ExecutiveBrief.available_to?(actor)

      @actor = actor
      @mailbox = LightekMail::Access.accounts(actor).where(user: actor).find(mailbox_id)
    end

    def invite!(item:, recipient:, cancel:)
      raise ActiveRecord::RecordNotFound unless item.user_id == @actor.id

      to = single_recipient!(recipient)
      item.with_lock do
        if item.closed_at? && !cancel
          raise ArgumentError, 'This agenda entry is closed. You can send a cancellation.'
        end

        invitee = NevaehCalendarInvitee.find_or_initialize_by(agenda_item: item, recipient: to)
        raise ArgumentError, 'Send an invitation before cancelling it.' if cancel && invitee.new_record?
        previous = invitee.persisted? ? invitee : NevaehCalendarInvitee.find_by(agenda_item: item)
        if previous && (previous.mailbox_id != @mailbox.id || previous.organizer_address != @mailbox.address)
          raise ArgumentError, 'Use the original organizer address for this event.'
        end
        if invitee.persisted? && invitee.cancelled? == cancel && (cancel || invitee.agenda_version == item.lock_version)
          return invitee.message
        end

        sequence = invitee.persisted? ? invitee.sequence + 1 : 0
        calendar = ExecutiveCalendar.attachment(item: item, organizer: @mailbox.address, attendee: to, cancel: cancel, sequence: sequence)
        action = cancel ? 'Cancelled' : 'Invitation'
        method = cancel ? 'CANCEL' : 'REQUEST'
        text = "#{action}: #{item.title}\n#{item.starts_at.iso8601} to #{item.ends_at.iso8601}"
        message = submit(to: to, subject: "#{action}: #{item.title}", text: text, key: ['calendar', item.id, sequence, method, to],
          uploads: [{io: StringIO.new(calendar), filename: 'meeting.ics', content_type: "text/calendar; method=#{method}; charset=UTF-8",
            byte_size: calendar.bytesize, identify: false}])
        invitee.update!(mailbox: @mailbox, organizer_address: @mailbox.address, message: message, sequence: sequence,
          agenda_version: item.lock_version, cancelled: cancel)
        message
      end
    end

    def request_booking!(record:, recipient:, instructions:)
      authorize_case!(record, 'travel')
      text = instructions.to_s.strip
      raise ArgumentError, 'Enter booking instructions up to 4,000 characters.' unless text.length.between?(1, 4_000)

      to = single_recipient!(recipient)
      submit(to: to, subject: "Booking request: #{record.title}", text: text, key: ['booking', record.id, to, text])
    end

    def send_screening!(record:, recipient:, license_id:)
      authorize_case!(record, 'screening')
      sites = LightekSettings::WebsiteIdentity.sites_for(@actor).where(tenant: @actor)
      license = Studio::Broadcasting::ProgramLicense.where(licensee_site: sites).find(license_id)
      Studio::Broadcasting::HostedPrograms.check_booking!(license)
      license.publish_web_screening!
      path = Rails.application.routes.url_helpers.broadcast_program_screening_path(license.web_screening_key)
      host = license.licensee_site.host
      unless /\A[a-z0-9][a-z0-9.-]*[a-z0-9]\z/i.match?(host)
        raise ArgumentError, 'The licensed screening needs a valid web hostname.'
      end

      url = URI::HTTPS.build(host: host, path: path).to_s
      to = single_recipient!(recipient)
      submit(to: to, subject: "Screening: #{license.title}", text: "Watch the licensed screening from the authorized Lightek website:\n#{url}",
        key: ['screening', record.id, license.id, license.web_screening_key, to])
    end

    private

    def authorize_case!(record, kind)
      raise ActiveRecord::RecordNotFound unless record.owner_id == @actor.id && record.kind == kind && record.status != 'closed'
    end

    def single_recipient!(value)
      recipients = LightekMail::Submission.addresses(value)
      raise ArgumentError, 'Send this handoff to one recipient at a time.' unless recipients.one?

      recipients.first
    end

    def submit(to:, subject:, text:, key:, uploads: [])
      id = Digest::SHA256.hexdigest(key.to_json)
      LightekMail::Submission.create!(account: @mailbox, attributes: {to: to, subject: subject.tr("\r\n", ' ').first(200), text: text},
        idempotency_key: "executive-#{id}", uploads: uploads)
    end
  end
end
