require "ice_cube"

module LightekMail
  module CalendarHistory
    Occurrence = Struct.new(:event, :starts_at, :ends_at, keyword_init: true)
    module_function

    def preview!(account:, upload:, team_mailbox:)
      events, issues = CalendarHistoryParser.parse(upload)
      account.with_lock do
        CalendarHistoryPreview.where("expires_at <= ?", Time.current).delete_all
        CalendarHistoryPreview.where(account: account).delete_all
        CalendarHistoryPreview.create!(account: account, team_mailbox: team_mailbox,
          events: events, issues: issues, expires_at: 30.minutes.from_now)
      end
    end

    def plan(account, events)
      existing = CalendarHistoryEvent.for_mailbox(account).where(uid: events.map { |event| event.fetch("uid") }.uniq)
        .pluck(:uid, :occurrence_key).to_set
      events.map do |event|
        identity = event.values_at("uid", "occurrence_key")
        [event, !existing.add?(identity)]
      end
    end

    def apply!(account, preview)
      account.with_lock do
        preview.reload
        raise ArgumentError, "This preview expired. Upload the calendar again." if preview.expires_at <= Time.current || preview.account_id != account.id

        rows = plan(account, preview.events)
        rows.each do |event, duplicate|
          CalendarHistoryEvent.for_mailbox(account).create!(event) unless duplicate
        end
        created = rows.count { |_, duplicate| !duplicate }
        if preview.team_mailbox
          preview.team_mailbox.update!(
            calendar_imported_at: rows.any? ? Time.current : preview.team_mailbox.calendar_imported_at,
            calendar_import_result: {imported: created, skipped: rows.size - created, unreadable: preview.issues.size}
          )
        end
        preview.destroy!
        [created, rows.size - created]
      end
    end

    def week(account, date)
      scope = CalendarHistoryEvent.for_mailbox(account)
      active = scope.where(cancelled: false).where.not(uid: scope.where(cancelled: true, occurrence_key: "").select(:uid))
      first = date.in_time_zone
      last = (date + 7).in_time_zone
      all_day_first = date.to_time(:utc)
      all_day_last = (date + 7).to_time(:utc)
      single_events = active.where(zone: nil).where(
        "(all_day = ? AND starts_at < ? AND (ends_at > ? OR starts_at >= ?)) OR " \
        "(all_day = ? AND starts_at < ? AND (ends_at > ? OR starts_at >= ?))",
        false, last, first, first, true, all_day_last, all_day_first, all_day_first
      ).order(:starts_at, :id).limit(150).map do |event|
        Occurrence.new(event: event, starts_at: event.starts_at, ends_at: event.ends_at)
      end
      recurring_events = []
      active.where.not(zone: nil).in_batches(of: 100) do |batch|
        masters = batch.to_a
        overrides = scope.where(uid: masters.map(&:uid)).where.not(occurrence_key: "").pluck(:uid, :occurrence_key).group_by(&:first)
        masters.each do |event|
          opening, closing = event.all_day? ? [all_day_first, all_day_last] : [first, last]
          recurring_events.concat(expand(event, opening, closing, overrides.fetch(event.uid, []).map(&:last)))
        end
        recurring_events = recurring_events.sort_by(&:starts_at).first(150)
      end
      (single_events + recurring_events).sort_by(&:starts_at).first(150)
    end

    def expand(event, opening, closing, overrides)
      duration = event.ends_at - event.starts_at
      start = event.starts_at.in_time_zone(event.zone)
      dates = [start] + event.added_dates.map { |value| Time.iso8601(value) }
      if event.rule
        schedule = IceCube::Schedule.new(start)
        schedule.add_recurrence_rule(IceCube::Rule.from_ical(event.rule))
        dates.concat(schedule.occurrences_between(opening - duration, closing).map(&:start_time))
      end
      excluded = (event.excluded_dates + overrides).map { |value| Time.iso8601(value).to_i }.to_set
      dates.uniq(&:to_i).filter_map do |occurrence|
        next if excluded.include?(occurrence.to_i)

        ends_at = occurrence + duration
        next unless occurrence < closing && (ends_at > opening || occurrence >= opening)

        Occurrence.new(event: event, starts_at: occurrence, ends_at: ends_at)
      end
    end
  end
end
