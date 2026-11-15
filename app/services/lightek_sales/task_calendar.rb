# frozen_string_literal: true
require 'digest'
module LightekSales
  module TaskCalendar
    def self.call(task)
      lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Lightek//Sales tasks//EN', 'BEGIN:VEVENT',
        "UID:lightek-sales-task-#{Digest::SHA256.hexdigest([task.site.host, task.site_id, task.id, task.created_at.iso8601(6)].join(':'))}@lightek.local", "DTSTAMP:#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}",
        "DTSTART:#{task.due_at.utc.strftime('%Y%m%dT%H%M%SZ')}", "DTEND:#{(task.due_at + 15.minutes).utc.strftime('%Y%m%dT%H%M%SZ')}",
        "SUMMARY:#{escape(task.title)}", "DESCRIPTION:#{escape("Sales follow-up. Status: #{task.status}. Complete or reschedule in Lightek Dashboard.")}",
        "STATUS:#{task.status == 'canceled' ? 'CANCELLED' : 'CONFIRMED'}", 'END:VEVENT', 'END:VCALENDAR']
      lines.map { |line| fold(line) }.join("\r\n") + "\r\n"
    end
    def self.escape(value)
      value.to_s.gsub('\\') { '\\\\' }.gsub(/\r\n|\r|\n/, '\\n').gsub(';', '\\;').gsub(',', '\\,')
    end
    def self.fold(line)
      chunks, current = [], +''
      line.each_char do |char|
        if current.bytesize + char.bytesize > 74
          chunks << current
          current = +' '
        end
        current << char
      end
      (chunks << current).join("\r\n")
    end
  end
end
