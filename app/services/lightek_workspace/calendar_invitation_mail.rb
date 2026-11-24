require 'stringio'
require 'time'

module LightekWorkspace
  module CalendarInvitationMail
    MAX_REPLY_BYTES = 64.kilobytes
    RESPONSES = {'ACCEPTED' => 'accepted', 'TENTATIVE' => 'tentative', 'DECLINED' => 'declined'}.freeze
    ADDRESS = /\A[a-z0-9][a-z0-9._+\-]{0,63}@[a-z0-9.\-]+\z/

    module_function

    def submit!(invitation, mailbox)
      event = invitation.event
      method = event.cancelled_at? ? 'CANCEL' : 'REQUEST'
      label = if event.cancelled_at?
        'Cancelled'
      elsif invitation.sequence.zero?
        'Invitation'
      else
        'Calendar update'
      end
      calendar = build(invitation, event, method)
      LightekMail::Submission.create!(account: mailbox, attributes: {
        to: [invitation.attendee_address], subject: "#{label}: #{event.title.gsub(/[\r\n]+/, ' ')}",
        text: "#{label}: #{event.title}\n#{event.starts_at.iso8601} – #{event.ends_at.iso8601}\n\n#{event.details}"
      }, idempotency_key: "#{ExternalInvitation::MESSAGE_PREFIX}#{invitation.id}_#{invitation.sequence}",
        uploads: [{io: StringIO.new(calendar), filename: 'meeting.ics', content_type: "text/calendar; method=#{method}; charset=UTF-8",
          byte_size: calendar.bytesize, identify: false}])
    end

    def build(invitation, event, method)
      cancelled = method == 'CANCEL'
      attendee = cancelled ? 'ATTENDEE' : 'ATTENDEE;RSVP=TRUE;PARTSTAT=NEEDS-ACTION'
      lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Lightek//Shared Calendar//EN', "METHOD:#{method}",
        'BEGIN:VEVENT', "UID:#{invitation.uid}", "DTSTAMP:#{timestamp(Time.current)}",
        "DTSTART:#{timestamp(event.starts_at)}", "DTEND:#{timestamp(event.ends_at)}", "SEQUENCE:#{invitation.sequence}",
        "STATUS:#{cancelled ? 'CANCELLED' : 'CONFIRMED'}", "ORGANIZER:mailto:#{invitation.organizer_address}",
        "#{attendee}:mailto:#{invitation.attendee_address}", "SUMMARY:#{LightekSales::TaskCalendar.escape(event.title)}",
        "DESCRIPTION:#{LightekSales::TaskCalendar.escape(event.details)}", 'END:VEVENT', 'END:VCALENDAR']
      lines.map { |line| LightekSales::TaskCalendar.fold(line) }.join("\r\n") + "\r\n"
    end

    def timestamp(time)
      time.utc.strftime('%Y%m%dT%H%M%SZ')
    end

    def record_reply(account:, envelope:, mail:)
      return false unless envelope.recipients.include?(account.address)

      from = Array(mail.from).map(&:downcase)
      return false unless from.one? && ADDRESS.match?(from.first)

      calendar_parts(mail).any? do |part|
        reply = parse_reply(part.decoded)
        reply && apply_reply(account, from.first, reply)
      end
    rescue ArgumentError, EncodingError, Mail::Field::ParseError
      false
    end

    def calendar_parts(part)
      return part.parts.flat_map { |child| calendar_parts(child) } if part.multipart?
      return [] unless part.mime_type == 'text/calendar' || part.filename.to_s.downcase.end_with?('.ics')
      mime_method = part.content_type_parameters&.fetch('method', nil)
      return [] if mime_method && !mime_method.casecmp?('REPLY')
      return [] if part.body.raw_source.bytesize > MAX_REPLY_BYTES * 2

      [part]
    end

    def parse_reply(source)
      return if source.bytesize > MAX_REPLY_BYTES

      lines = source.to_s.b.gsub(/\r?\n[ \t]/, '').split(/\r?\n/).reject(&:empty?)
      return unless lines.first&.casecmp?('BEGIN:VCALENDAR') && lines.last&.casecmp?('END:VCALENDAR')

      boundaries = lines.each_index.select { |index| lines[index].match?(/\A(?:BEGIN|END):VEVENT\z/i) }
      return unless boundaries.size == 2

      first, last = boundaries
      return unless lines[first].casecmp?('BEGIN:VEVENT') && lines[last].casecmp?('END:VEVENT')
      return unless property(lines[1...first], 'METHOD')&.last&.casecmp?('REPLY')

      properties = lines[(first + 1)...last]
      return if properties.any? { |line| line.match?(/\A(?:BEGIN|END|RECURRENCE-ID)[:;]/i) }

      uid = property(properties, 'UID')&.last
      organizer = property(properties, 'ORGANIZER')&.last
      sequence_line = properties.any? { |line| line.match?(/\ASEQUENCE[:;]/i) }
      sequence = sequence_line ? property(properties, 'SEQUENCE')&.last : '0'
      stamp = property(properties, 'DTSTAMP')&.last
      attendee = property(properties, 'ATTENDEE')
      response = RESPONSES[attendee&.first&.match(/(?:\A|;)PARTSTAT=(ACCEPTED|TENTATIVE|DECLINED)(?=;|\z)/i)&.[](1)&.upcase]
      return unless response && uid&.match?(/\A[0-9a-f-]{36}@calendar\.lightek\z/) &&
        sequence&.match?(/\A[0-9]{1,10}\z/) && stamp&.match?(/\A[0-9]{8}T[0-9]{6}Z\z/)

      {uid: uid, organizer: organizer, attendee: attendee.last, sequence: sequence.to_i,
        timestamp: Time.strptime(stamp, '%Y%m%dT%H%M%S%Z'), response: response}
    end

    def property(lines, name)
      matches = lines.filter_map do |line|
        line.match(/\A#{name}((?:;[A-Z0-9-]+=(?:"[^"]*"|[^:;]*))*):(.*)\z/i)&.captures
      end
      matches.first if matches.one?
    end

    def apply_reply(account, from, reply)
      return false unless reply[:attendee].casecmp?("mailto:#{from}") &&
        reply[:organizer]&.casecmp?("mailto:#{account.address}") && reply[:timestamp] <= 5.minutes.from_now

      invitation = ExternalInvitation.find_by(uid: reply[:uid], mailbox_id: account.id,
        organizer_address: account.address, attendee_address: from)
      return false unless invitation

      invitation.with_lock do
        next false if invitation.event.cancelled_at? || invitation.sequence != reply[:sequence] ||
          (invitation.reply_timestamp && invitation.reply_timestamp >= reply[:timestamp])

        invitation.update!(response: reply[:response], reply_timestamp: reply[:timestamp])
      end
    end
  end
end
