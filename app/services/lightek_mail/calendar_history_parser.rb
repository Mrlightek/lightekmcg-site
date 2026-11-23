require "icalendar"

module LightekMail
  module CalendarHistoryParser
    MAX_BYTES = 2.megabytes
    MAX_EVENTS = 2_000
    FIELDS = %w[UID SUMMARY DESCRIPTION LOCATION DTSTART DTEND DURATION RRULE RDATE EXDATE RECURRENCE-ID STATUS].freeze
    DAY = /(?:MO|TU|WE|TH|FR|SA|SU)/
    FREQUENCIES = %w[DAILY WEEKLY MONTHLY YEARLY].freeze
    DATE_YEARS = (1900..2200)

    module_function

    def parse(upload)
      raise ArgumentError, "Choose an iCalendar (.ics) file." unless upload.respond_to?(:tempfile)

      source = upload.tempfile.read(MAX_BYTES + 1).to_s.force_encoding(Encoding::UTF_8)
      unless source.valid_encoding? && source.bytesize.between?(1, MAX_BYTES) && !source.include?("\0")
        raise ArgumentError, "Use a UTF-8 .ics file up to 2 MB."
      end

      components = calendar_components(source.delete_prefix("\uFEFF"))
      events = []
      issues = []
      components.each_with_index do |component, index|
        events << parse_event(component)
      rescue ArgumentError, Icalendar::Parser::ParseError, TZInfo::InvalidTimezoneIdentifier,
             TZInfo::PeriodNotFound, TZInfo::AmbiguousTime
        issues << index + 1
      end
      [events, issues]
    end

    def calendar_components(source)
      lines = source.gsub(/\r?\n[ \t]/, "").lines.map(&:chomp).reject(&:empty?)
      stack = []
      events = []
      current = nil
      calendar_count = 0
      lines.each do |line|
        key, value = line.split(":", 2)
        case key.upcase
        when "BEGIN"
          component = value.to_s.upcase
          raise ArgumentError, "The iCalendar file has invalid component boundaries." if stack.size >= 4 || (stack.empty? && component != "VCALENDAR")

          calendar_count += 1 if stack.empty?
          current = [] if component == "VEVENT" && stack == ["VCALENDAR"]
          stack << component
        when "END"
          raise ArgumentError, "The iCalendar file has invalid component boundaries." unless stack.pop == value.to_s.upcase

          if current && stack == ["VCALENDAR"] && value.casecmp?("VEVENT")
            events << current
            current = nil
            raise ArgumentError, "Choose an export with at most 2,000 events." if events.size > MAX_EVENTS
          end
        else
          if stack == ["VCALENDAR"] && key.casecmp?("METHOD") && !value.to_s.casecmp?("PUBLISH")
            raise ArgumentError, "Choose a calendar export file."
          end
          current << line if current && stack == %w[VCALENDAR VEVENT]
        end
      end
      unless stack.empty? && calendar_count == 1 && events.any?
        raise ArgumentError, "The file must contain one calendar with at least one event."
      end

      events
    end

    def parse_event(lines)
      fields = lines.group_by { |line| line.split(/[:;]/, 2).first.upcase }.slice(*FIELDS)
      unless fields.key?("UID") && (fields.keys - %w[RDATE EXDATE]).all? { |key| fields.fetch(key).one? }
        raise ArgumentError
      end

      recurrence_line = fields.dig("RECURRENCE-ID", 0)
      raise ArgumentError if recurrence_line&.match?(/;RANGE=/i) || fields.key?("DTEND") && fields.key?("DURATION")
      raise ArgumentError if recurrence_line && (fields.keys & %w[RRULE RDATE EXDATE]).any?

      # Restrict the parser to known event fields. The time-zone resolver uses
      # known zone IDs without executing recurrence rules from embedded zones.
      body = fields.except("RDATE", "EXDATE", "RRULE").values.flatten
      event = Icalendar::Calendar.parse(["BEGIN:VCALENDAR", "BEGIN:VEVENT", *body, "END:VEVENT", "END:VCALENDAR"].join("\r\n")).first.events.first
      uid = event.uid.to_s
      raise ArgumentError if uid.blank? || uid.length > 255 || uid.match?(/[[:cntrl:]]/)

      recurrence = CalendarNotice.calendar_time(event.recurrence_id) if recurrence_line
      raise ArgumentError if recurrence_line && !recurrence

      cancelled = event.status.to_s.casecmp?("CANCELLED")
      period = CalendarNotice.event_period(event)
      if cancelled && recurrence && !period
        period = {"starts_at" => recurrence.iso8601, "ends_at" => recurrence.iso8601, "all_day" => event.recurrence_id.is_a?(Icalendar::Values::Date)}
      end
      raise ArgumentError unless period && DATE_YEARS.cover?(Time.iso8601(period.fetch("starts_at")).year)

      zone = event.dtstart&.value
      zone = zone.is_a?(ActiveSupport::TimeWithZone) ? zone.time_zone.tzinfo.identifier : "UTC"
      zone = nil unless (fields.keys & %w[RRULE RDATE EXDATE]).any?
      if zone && Time.iso8601(period.fetch("ends_at")) - Time.iso8601(period.fetch("starts_at")) > 366.days
        raise ArgumentError
      end
      all_day = period.fetch("all_day")
      rule = validated_rule(fields.dig("RRULE", 0)&.split(":", 2)&.last, all_day)
      period.merge("uid" => uid, "occurrence_key" => recurrence&.iso8601 || "", "cancelled" => cancelled,
        "title" => event.summary.to_s.strip.slice(0, 160).presence || "Untitled event",
        "location" => event.location.to_s.slice(0, 300), "description" => event.description.to_s.slice(0, 4_000),
        "zone" => zone, "rule" => rule,
        "added_dates" => recurrence_dates(fields.fetch("RDATE", []), all_day),
        "excluded_dates" => recurrence_dates(fields.fetch("EXDATE", []), all_day))
    end

    def recurrence_dates(lines, all_day)
      raise ArgumentError if lines.sum { |line| line.count(",") + 1 } > 500

      values = lines.flat_map do |line|
        name, dates = line.split(":", 2)
        dates.to_s.split(",", -1).map do |value|
          raise ArgumentError unless value.match?(/\A\d{8}(?:T\d{6}Z?)?\z/i)
          prefix = name.sub(/\A(?:RDATE|EXDATE)/i, "DTSTART")
          event = Icalendar::Calendar.parse("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n#{prefix}:#{value}\r\nEND:VEVENT\r\nEND:VCALENDAR").first.events.first
          time = CalendarNotice.calendar_time(event.dtstart)
          raise ArgumentError unless time && DATE_YEARS.cover?(time.year) && all_day == event.dtstart.is_a?(Icalendar::Values::Date)

          time.iso8601
        end
      end
      values.uniq
    end

    def validated_rule(rule, all_day)
      return unless rule
      rule = rule.upcase
      pieces = rule.split(";").map { |piece| piece.split("=", 2) }
      parts = pieces.to_h
      raise ArgumentError unless parts.size == pieces.size && FREQUENCIES.include?(parts["FREQ"])

      parts.except("FREQ").each do |key, value|
        valid = case key
                when "INTERVAL" then value&.match?(/\A\d{1,3}\z/) && value.to_i.between?(1, 366)
                when "COUNT" then value&.match?(/\A\d{1,6}\z/) && value.to_i.between?(1, 10_000)
                when "UNTIL" then value&.match?(/\A\d{8}(?:T\d{6}Z)?\z/) && DATE_YEARS.cover?(value[0, 4].to_i)
                when "WKST" then value&.match?(/\A#{DAY}\z/)
                when "BYDAY"
                  ordinal = parts["FREQ"] == "MONTHLY" ? "(?:[+-]?[1-5])?" : ""
                  list_matches?(value, /\A#{ordinal}#{DAY}\z/, 35)
                when "BYMONTH" then list_matches?(value, /\A(?:[1-9]|1[0-2])\z/, 12)
                when "BYMONTHDAY" then list_matches?(value, /\A-?(?:[1-9]|[12][0-9]|3[01])\z/, 62)
                end
        raise ArgumentError unless valid
      end
      raise ArgumentError if parts.key?("COUNT") && parts.key?("UNTIL")
      if (until_value = parts["UNTIL"])
        raise ArgumentError unless all_day == (until_value.length == 8)
        Date.strptime(until_value[0, 8], "%Y%m%d")
        Time.strptime(until_value, "%Y%m%dT%H%M%S%Z") unless all_day
      end
      IceCube::Rule.from_ical(rule)
      rule
    end

    def list_matches?(value, pattern, limit)
      return false unless value
      pieces = value.split(",", -1)
      pieces.size.between?(1, limit) && pieces.all? { |piece| pattern.match?(piece) }
    end
  end
end
