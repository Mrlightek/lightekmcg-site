# frozen_string_literal: true
module NevaehIntelligences
  module Islamic
    module StudyClock
      module_function
      def zone
        configured = Rails.respond_to?(:application) && Rails.application&.config&.time_zone
        Time.find_zone!(configured.presence || Time.zone&.name || 'UTC')
      end
      def windows(routine, date:)
        # The application server's configured zone is used explicitly, even if a
        # request temporarily changes Time.zone for a signed-in browser user.
        starts = [date, date + 1].flat_map do |day|
          routine.daily_times.filter_map do |slot, value|
            hour, minute = value.split(':').map(&:to_i)
            time = zone.local(day.year, day.month, day.day, hour, minute)
            # A clock time missing during a DST spring-forward is skipped.
            next unless time.strftime('%H:%M') == value
            {slot: slot, local_date: day, scheduled_at: time}
          end
        end.sort_by { |entry| entry[:scheduled_at] }
        starts.each_with_index.filter_map do |entry, index|
          next unless entry[:local_date] == date
          stop = entry[:scheduled_at] + routine.window_minutes.minutes
          following = starts[index + 1]&.fetch(:scheduled_at)
          entry.merge(ends_at: following ? [stop, following].min : stop)
        end
      end
      def due(routine, now: Time.current)
        day = now.in_time_zone(zone).to_date
        # Include yesterday's late slot if its study window crosses midnight.
        [day - 1, day].flat_map { |date| windows(routine, date: date) }
          .select { |entry| entry[:scheduled_at] <= now && now < entry[:ends_at] }
      end
    end
  end
end
