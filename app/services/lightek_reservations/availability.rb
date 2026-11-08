# frozen_string_literal: true
module LightekReservations
  module Availability
    class Invalid < StandardError; end
    module_function
    # A local form must name an unambiguous wall time; API callers may send an
    # ISO 8601 timestamp with an explicit UTC offset during the DST fall-back.
    def parse(value, resource)
      text = value.to_s
      return Time.iso8601(text) if text.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
      local = DateTime.iso8601(text)
      zone = ActiveSupport::TimeZone[resource.timezone]
      periods = zone.tzinfo.periods_for_local(local)
      raise Invalid, 'This local time is missing or ambiguous because of daylight saving time. Choose another time or include a UTC offset.' unless periods.one?
      zone.local(local.year, local.month, local.day, local.hour, local.minute, local.second)
    rescue ArgumentError
      raise Invalid, 'Enter a valid date and time'
    end
    def check!(resource:, starts_at:, ends_at:, quantity: 1, excluding: nil, now: Time.current)
      raise Invalid, 'This experience is unavailable' unless resource.published?
      raise Invalid, 'Invalid reservation length' unless ends_at > starts_at
      raise Invalid, 'Book further in advance' if starts_at < now + resource.notice_minutes.minutes
      raise Invalid, 'Choose a date within the next year' if starts_at > now + 1.year
      raise Invalid, 'Invalid party size' unless quantity.between?(1, resource.capacity)
      from, until_time = starts_at - resource.buffer_minutes.minutes, ends_at + resource.buffer_minutes.minutes
      raise Invalid, 'This time is blocked' if resource.blackouts.where('starts_at < ? AND ends_at > ?', until_time, from).exists?
      unless resource.server? || resource.hours.empty?
        zone = ActiveSupport::TimeZone[resource.timezone]
        local_start, local_end = starts_at.in_time_zone(zone), ends_at.in_time_zone(zone)
        windows = resource.hours.fetch(local_start.wday.to_s, [])
        open = local_start.to_date == local_end.to_date && windows.any? do |opening, closing|
          local_start.strftime('%H:%M') >= opening && local_end <= zone.parse("#{local_end.to_date} #{closing}")
        end
        raise Invalid, 'Choose a time within opening hours' unless open
      end
      # Server capacity is controlled by product inventory and the provisioning
      # pipeline; each reservation allocates an isolated server, never a shared slot.
      return true if resource.server?
      rows = resource.reservations.occupying.where('blocks_from < ? AND blocks_until > ?', until_time, from)
      rows = rows.where.not(id: excluding.id) if excluding
      events = rows.pluck(:blocks_from, :blocks_until, :quantity).flat_map do |a, b, qty|
        [[[a, from].max, qty], [[b, until_time].min, -qty]]
      end
      occupancy = 0
      events.sort_by { |time, delta| [time, delta] }.each do |_time, delta|
        occupancy += delta
        raise Invalid, 'This time has no remaining capacity' if occupancy + quantity > resource.capacity
      end
      true
    end
    def slots(resource:, date:)
      day = Date.iso8601(date.to_s)
      zone = ActiveSupport::TimeZone[resource.timezone]
      raise Invalid, 'Choose a date within the next year' unless (Date.current..1.year.from_now.to_date).cover?(day)
      windows = resource.hours.empty? ? [['09:00', '17:00']] : resource.hours.fetch(day.wday.to_s, [])
      windows.flat_map do |opening, closing|
        start = zone.parse("#{day} #{opening}")
        finish = zone.parse("#{day} #{closing}")
        result = []
        while start + resource.duration_minutes.minutes <= finish
          begin
            check!(resource: resource, starts_at: start, ends_at: start + resource.duration_minutes.minutes)
            result << start.iso8601
          rescue Invalid
            # Occupied or outside the advance-notice window.
          end
          start += resource.duration_minutes.minutes
        end
        result
      end.uniq
    rescue Date::Error
      raise Invalid, 'Choose a valid date'
    end
  end
end
