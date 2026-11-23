require "stringio"
require "time"

module LightekMail
  module IncomingCalendar
    REPLY_PREFIX = "calendar_rsvp_".freeze
    RESPONSES = {"accepted" => "Accept", "tentative" => "Tentative", "declined" => "Decline"}.freeze

    module_function

    def current_reply?(account, message)
      CalendarInvitation.for_mailbox(account).exists?(reply_message_id: message.id, cancelled: false)
    end

    # Inbound holds the sending policy and account locks, in that order.
    def receive!(message, mail:, envelope:, scan:)
      account = message.account
      notice = CalendarNotice.from_mail(mail, account: account, envelope: envelope, scan: scan)
      return unless notice

      message.update!(calendar_notice: notice)
      apply!(account, message) if !message.junk? && notice.fetch("trusted")
    end

    def review!(account, message, choice:)
      raise ArgumentError, "Choose a calendar response." unless choice == "apply" || RESPONSES.key?(choice)

      SendingPolicy.synchronize do
        account.with_lock do
          message.reload
          notice = message.calendar_notice
          if message.account_id != account.id || message.direction != "inbound" ||
              message.junk? || message.trashed? || notice.blank? || notice["attendee"] != account.address
            raise ArgumentError, "This calendar notice is unavailable for this mailbox."
          end
          if choice == "apply"
            invitation = apply!(account, message)
            raise ArgumentError, "A newer calendar notice is already on file." unless invitation.source_message_id == message.id
          else
            respond!(account, message, choice)
          end
        end
      end
    end

    def apply!(account, message)
      notice = message.calendar_notice
      invitation = CalendarInvitation.for_notice(account, notice) || CalendarInvitation.new(
        account: account, attendee: account.address, organizer: notice.fetch("organizer"), uid: notice.fetch("uid"),
        title: "Cancelled invitation"
      )
      version = [notice.fetch("sequence"), Time.iso8601(notice.fetch("stamp"))]
      return invitation if invitation.persisted? && (invitation.version <=> version) >= 0

      if notice.fetch("method") == "CANCEL"
        invitation.cancelled = true
      else
        invitation.assign_attributes(notice.slice("title", "description", "location", "starts_at", "ends_at", "all_day"))
        invitation.cancelled = false
      end
      invitation.update!(sequence: version.first, stamp: version.last, source_message: message, reply_message: nil)
      invitation
    end

    def respond!(account, message, choice)
      notice = message.calendar_notice
      raise ArgumentError, "A cancellation cannot be answered." if notice.fetch("method") != "REQUEST"

      invitation = apply!(account, message)
      if invitation.cancelled? || invitation.source_message_id != message.id
        raise ArgumentError, "Open the latest calendar invitation before responding."
      end

      previous = invitation.reply_message
      if previous&.state == "uncertain"
        raise Submission::Unavailable, "Delivery of your previous RSVP could not be confirmed. Check Mail before sending again."
      end

      return invitation if choice == invitation.response && previous && previous.state != "failed"

      revision = invitation.response_revision + 1
      stamp = Time.current.utc.change(usec: 0)
      stamp = invitation.reply_stamp + 1.second if invitation.reply_stamp && invitation.reply_stamp >= stamp
      reply = submit_reply!(account, invitation, message, choice, revision, stamp)
      invitation.update!(response: choice, response_revision: revision, reply_message: reply, reply_stamp: stamp)
      invitation
    end

    def submit_reply!(account, invitation, message, choice, revision, stamp)
      calendar = Icalendar::Calendar.new
      calendar.prodid = "-//Lightek//Mail Calendar//EN"
      calendar.reply
      calendar.event do |event|
        event.uid = invitation.uid
        event.sequence = invitation.sequence
        event.dtstamp = Icalendar::Values::DateTime.new(stamp.utc, "tzid" => "UTC")
        event.organizer = "mailto:#{invitation.organizer}"
        event.attendee = Icalendar::Values::CalAddress.new("mailto:#{invitation.attendee}", "partstat" => choice.upcase)
      end
      data = calendar.to_ical
      body = "Response: #{choice.capitalize}\n#{invitation.title}"
      subject = "#{choice.capitalize}: #{invitation.title.gsub(/[\r\n]+/, ' ')}"
      Submission.create!(account: account, attributes: {to: [invitation.organizer], subject: subject, text: body,
        in_reply_to: message.message_id}, idempotency_key: "#{REPLY_PREFIX}#{invitation.id}_#{revision}",
        uploads: [{io: StringIO.new(data), filename: "response.ics", content_type: "text/calendar; method=REPLY; charset=UTF-8",
          byte_size: data.bytesize, identify: false}])
    end
  end
end
