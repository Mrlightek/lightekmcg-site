# frozen_string_literal: true

require 'digest'

module NevaehOs
  module ExecutiveCalendar
    module_function

    def attachment(item:, organizer: nil, attendee: nil, cancel: false, sequence: 0)
      method = cancel ? 'CANCEL' : 'REQUEST'
      identity = Digest::SHA256.hexdigest([item.user_id, item.id, item.created_at.iso8601(6)].join(':'))
      lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Lightek//Executive agenda//EN', 'CALSCALE:GREGORIAN']
      lines << "METHOD:#{method}" if attendee
      lines.concat(['BEGIN:VEVENT', "UID:executive-#{identity}@lightek.local", "DTSTAMP:#{timestamp(item.updated_at)}",
        "DTSTART:#{timestamp(item.starts_at)}", "DTEND:#{timestamp(item.ends_at)}",
        "SEQUENCE:#{sequence}", "SUMMARY:#{LightekSales::TaskCalendar.escape(item.title)}",
        "STATUS:#{cancel ? 'CANCELLED' : 'CONFIRMED'}"])
      if attendee
        lines << "ORGANIZER:mailto:#{organizer}"
        lines << "ATTENDEE;RSVP=TRUE:mailto:#{attendee}"
      end
      lines.concat(%w[END:VEVENT END:VCALENDAR])
      lines.map { |line| LightekSales::TaskCalendar.fold(line) }.join("\r\n") + "\r\n"
    end

    def timestamp(time)
      time.utc.strftime('%Y%m%dT%H%M%SZ')
    end
  end
end
