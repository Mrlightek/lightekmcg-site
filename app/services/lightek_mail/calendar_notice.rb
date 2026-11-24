require "icalendar"
require "time"

module LightekMail
  module CalendarNotice
    MAX_BYTES = 64.kilobytes
    ADDRESS = /\A[a-z0-9][a-z0-9._+\-]{0,63}@[a-z0-9.\-]+\.[a-z]{2,63}\z/i
    EVENT_PROPERTIES = %w[UID ORGANIZER ATTENDEE DTSTART DTEND DURATION DTSTAMP SEQUENCE SUMMARY DESCRIPTION LOCATION].freeze
    RECURRING = %w[RRULE RDATE EXDATE EXRULE RECURRENCE-ID].freeze
    REQUIRED = %w[UID ORGANIZER DTSTAMP].freeze
    METHODS = %w[REQUEST CANCEL].freeze
    PROVIDER_SENDERS = %w[calendar-notification@google.com].freeze

    module_function

    def from_mail(mail, account:, envelope:, scan:)
      return unless envelope.recipients.include?(account.address)
      return unless Array(mail.from).one?

      sender = mail.from.first.downcase
      return unless ADDRESS.match?(sender)

      notices = parts(mail).filter_map do |part|
        parse_part(part, account.address)
      end.uniq
      return unless notices.one?

      notice = notices.first
      aligned = Array(scan&.fetch("dkim_domains", nil)).include?(sender.split("@").last)
      recognizes_sender = sender == notice.fetch("organizer") || PROVIDER_SENDERS.include?(sender)
      notice.merge("trusted" => aligned && recognizes_sender)
    end

    def parts(part, depth = 0)
      return [] if depth > 8
      return part.parts.flat_map { |child| parts(child, depth + 1) } if part.multipart?
      return [] unless part.mime_type == "text/calendar" || part.filename.to_s.downcase.end_with?(".ics")
      return [] if part.body.raw_source.bytesize > MAX_BYTES * 2

      [part]
    end

    def parse_part(part, attendee)
      data = part.decoded
      return if data.bytesize > MAX_BYTES || data.include?("\0")

      method, calendar_data, properties = invitation_data(data)
      return unless calendar_data
      return if properties.key?("DTEND") && properties.key?("DURATION")

      mime_method = part.content_type_parameters&.fetch("method", nil)
      return if mime_method && !mime_method.casecmp?(method)

      event = Icalendar::Calendar.parse(calendar_data).first&.events&.first
      return unless event

      uid = event.uid.to_s
      organizer = address(event.organizer)
      attendees = event.attendee.map { |person| address(person) }
      return if uid.blank? || uid.length > 255 || uid.match?(/[[:cntrl:]]/) || !organizer
      return if method == "REQUEST" && !attendees.include?(attendee)
      return if method == "CANCEL" && attendees.any? && !attendees.include?(attendee)

      sequence_text = properties.dig("SEQUENCE", 0)&.split(":", 2)&.last || "0"
      return unless sequence_text.match?(/\A\d{1,10}\z/) && sequence_text.to_i <= 2_147_483_647
      stamp_line = properties.fetch("DTSTAMP").first
      return unless stamp_line.match?(/\ADTSTAMP:\d{8}T\d{6}Z\z/i)

      stamp = Time.strptime(stamp_line.split(":", 2).last, "%Y%m%dT%H%M%S%Z").utc
      return if stamp.year < 1900 || stamp > 10.minutes.from_now

      notice = {"uid" => uid, "organizer" => organizer, "attendee" => attendee, "method" => method,
        "sequence" => sequence_text.to_i, "stamp" => stamp.iso8601}
      return notice if method == "CANCEL"

      period = event_period(event)
      return unless period

      notice.merge(period).merge("title" => event.summary.to_s.strip.slice(0, 160).presence || "Calendar invitation",
        "description" => event.description.to_s.slice(0, 4000), "location" => event.location.to_s.slice(0, 300))
    rescue ArgumentError, EncodingError, Icalendar::Parser::ParseError, Mail::Field::ParseError, TZInfo::InvalidTimezoneIdentifier,
           TZInfo::PeriodNotFound, TZInfo::AmbiguousTime
      nil
    end

    # Only pass the selected VEVENT properties to the parser. Embedded alarms,
    # components and sender-defined timezone recurrence rules are never evaluated.
    def invitation_data(data)
      unfolded = data.b.gsub(/\r?\n[ \t]/, "").force_encoding(Encoding::UTF_8)
      return unless unfolded.valid_encoding?

      lines = unfolded.lines.map(&:chomp)
      return unless lines.first&.casecmp?("BEGIN:VCALENDAR") && lines.last&.casecmp?("END:VCALENDAR")

      stack = []
      method = nil
      count = 0
      properties = {}
      lines.each do |line|
        key = line.split(/[:;]/, 2).first.to_s.upcase
        case key
        when "BEGIN"
          component = line.split(":", 2).last.to_s.upcase
          return if stack.size >= 4 || (stack.empty? && component != "VCALENDAR")
          count += 1 if stack == ["VCALENDAR"] && component == "VEVENT"
          stack << component
        when "END"
          return unless stack.pop == line.split(":", 2).last.to_s.upcase
        when "METHOD"
          next unless stack == ["VCALENDAR"]
          return if method
          method = line.split(":", 2).last.to_s.upcase
        else
          next unless stack == %w[VCALENDAR VEVENT]
          return if RECURRING.include?(key)
          next unless EVENT_PROPERTIES.include?(key)
          return if key != "ATTENDEE" && properties.key?(key)

          (properties[key] ||= []) << line
        end
      end
      return unless stack.empty? && count == 1 && METHODS.include?(method) && (REQUIRED - properties.keys).empty?

      serialized = ["BEGIN:VCALENDAR", "VERSION:2.0", "METHOD:#{method}", "BEGIN:VEVENT",
        *properties.values.flatten, "END:VEVENT", "END:VCALENDAR"].join("\r\n")
      [method, serialized, properties]
    end

    def event_period(event)
      start_value = event.dtstart
      return unless start_value

      all_day = start_value.is_a?(Icalendar::Values::Date)
      start_at = calendar_time(start_value)
      return unless start_at

      end_value = event.dtend
      end_at = if end_value
        return unless all_day == end_value.is_a?(Icalendar::Values::Date)
        calendar_time(end_value)
      elsif event.duration
        duration = event.duration
        return unless duration.is_a?(Icalendar::Values::Duration)
        return if duration.past? || (all_day && [duration.hours, duration.minutes, duration.seconds].any?(&:positive?))
        return if duration.weeks > 520 || duration.days > 3660 || duration.hours > 87_840 ||
          duration.minutes > 5_270_400 || duration.seconds > 316_224_000

        local_start = start_value.value
        local_start = start_at unless local_start.is_a?(ActiveSupport::TimeWithZone)
        (local_start.advance(weeks: duration.weeks, days: duration.days) +
          duration.hours.hours + duration.minutes.minutes + duration.seconds).utc
      elsif all_day
        start_at + 1.day
      else
        start_at
      end
      return unless end_at && start_at.year.between?(1900, 9998) && end_at.year.between?(1900, 9998) &&
        end_at >= start_at && (!all_day || end_at > start_at)

      {"starts_at" => start_at.iso8601, "ends_at" => end_at.iso8601, "all_day" => all_day}
    end

    def calendar_time(value)
      if value.is_a?(Icalendar::Values::Date)
        Time.utc(value.year, value.month, value.day)
      elsif value.is_a?(Icalendar::Values::DateTime)
        # The parser resolves IANA and Windows IDs to a TimeWithZone. A
        # floating or unknown local time has no reliable UTC instant.
        return unless value.tz_utc || value.value.is_a?(ActiveSupport::TimeWithZone)

        if value.value.is_a?(ActiveSupport::TimeWithZone)
          value.value.utc
        else
          value.value.to_datetime.new_offset(0).to_time.utc
        end
      end
    end

    def address(value)
      candidate = value.to_s.sub(/\Amailto:/i, "").downcase
      candidate if value.to_s.match?(/\Amailto:/i) && candidate.bytesize <= 254 && ADDRESS.match?(candidate)
    end
  end
end
