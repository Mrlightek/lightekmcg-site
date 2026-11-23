class Dashboard::SharedCalendarsController < Dashboard::SharedWorkspaceController
  before_action :load_calendar, except: %i[index create]
  rescue_from ActiveRecord::RecordInvalid, ArgumentError do |error|
    redirect_to(@calendar ? dashboard_shared_calendar_path(@calendar, employer_id: @employer.id) : dashboard_shared_calendars_path(employer_id: @employer.id),
      alert: error.message, status: :see_other)
  end

  def index
    @calendars = calendars.order(:name, :id).limit(100)
  end

  def create
    owner!
    calendar = calendars.create!(name: params.require(:name))
    redirect_to dashboard_shared_calendar_path(calendar, employer_id: @employer.id), status: :see_other
  end

  def show
    @date = params[:date].present? ? Date.iso8601(params[:date]) : Date.current
    first = @date.in_time_zone
    last = advance_week(first)
    @events = @calendar.events.scheduled.during(first, last).includes(:organizer, guests: :user).order(:starts_at, :id).limit(150)
    @coworkers = @workspace.roster.order(:first_name, :last_name, :id)
    if params[:availability_user_id].present?
      @person = @coworkers.find(params[:availability_user_id])
      @busy = busy_events(@person, first, last).order(:starts_at, :ends_at).limit(150).pluck(:starts_at, :ends_at)
    end
  end

  def schedule
    values = params.require(:event).permit(:title, :details, :starts_at, :ends_at, :repeat_frequency, :repeat_count, guest_ids: [])
    frequency = values.delete(:repeat_frequency)
    count = values.delete(:repeat_count)
    ids = Array(values.delete(:guest_ids)).reject(&:blank?).uniq
    raise ArgumentError, 'Invite up to 50 teammates.' if ids.size > 50

    guests = @workspace.roster.find(ids).reject { |user| user.id == current_user.id }
    attributes = values.merge(organizer: current_user)
    event = @calendar.with_lock do
      draft = @calendar.events.build(attributes)
      occurrences = draft.repeat_attributes(frequency: frequency, count: count)
      scheduled = occurrences.map do |period|
        occurrence = @calendar.events.create!(attributes.merge(period))
        guests.each { |guest| occurrence.guests.create!(user: guest) }
        occurrence
      end
      label = scheduled.size == 1 ? 'Shared calendar invitation' : 'Recurring calendar invitation'
      guests.each { |guest| notify(guest, scheduled.first, label) }
      scheduled.first
    end
    back(date: event.starts_at.to_date)
  end

  def reschedule
    event = @calendar.events.scheduled.find(params[:event_id])
    raise LightekPeople::Access::Denied unless @owner || event.organizer_id == current_user.id

    values = params.require(:event).permit(:title, :details, :starts_at, :ends_at)
    event.with_lock do
      raise ActiveRecord::RecordNotFound if event.cancelled_at?

      event.update!(values)
      if event.saved_change_to_starts_at? || event.saved_change_to_ends_at?
        event.guests.update_all(response: 'pending', updated_at: Time.current)
      end
      @workspace.roster.where(id: event.guests.select(:user_id)).each do |guest|
        notify(guest, event, 'Shared calendar event updated')
      end
    end
    back(date: event.starts_at.to_date)
  end

  def respond
    response_value = params.require(:response)
    raise ArgumentError, 'Choose a valid response.' unless %w[accepted tentative declined].include?(response_value)

    event = @calendar.events.scheduled.find(params[:event_id])
    event.with_lock do
      raise ActiveRecord::RecordNotFound if event.cancelled_at?
      event.guests.find_by!(user: current_user).update!(response: response_value)
    end
    back
  end

  def cancel
    event = @calendar.events.find(params[:event_id])
    raise LightekPeople::Access::Denied unless @owner || event.organizer_id == current_user.id

    @calendar.with_lock do
      occurrences = if params[:scope] == 'following' && event.series_key?
        @calendar.events.scheduled.where(series_key: event.series_key).where('starts_at >= ?', event.starts_at)
      else
        @calendar.events.scheduled.where(id: event.id)
      end
      recipients = LightekWorkspace::EventGuest.where(event_id: occurrences.select(:id)).select(:user_id)
      guests = @workspace.roster.where(id: recipients).to_a
      count = occurrences.update_all(cancelled_at: Time.current, updated_at: Time.current)
      if count.positive?
        label = count == 1 ? 'Shared calendar event cancelled' : 'Recurring calendar events cancelled'
        guests.each { |guest| notify(guest, event, label) }
      end
    end
    back
  end

  def ics
    event = @calendar.events.scheduled.find(params[:event_id])
    time = ->(value) { value.utc.strftime('%Y%m%dT%H%M%SZ') }
    uid = Digest::SHA256.hexdigest([request.host, event.id, event.created_at.to_i].join(':'))
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Lightek//Shared Calendar//EN', 'BEGIN:VEVENT',
      "UID:#{uid}@lightek", "DTSTAMP:#{time.call(event.updated_at)}", "DTSTART:#{time.call(event.starts_at)}",
      "DTEND:#{time.call(event.ends_at)}", "SUMMARY:#{LightekSales::TaskCalendar.escape(event.title)}",
      "DESCRIPTION:#{LightekSales::TaskCalendar.escape(event.details)}", 'END:VEVENT', 'END:VCALENDAR']
    send_data lines.map { |line| LightekSales::TaskCalendar.fold(line) }.join("\r\n") + "\r\n",
      filename: 'shared-event.ics', type: 'text/calendar', disposition: 'attachment'
  end

  private

  def advance_week(first) = first.advance(days: 7)
  def calendars = LightekWorkspace::Calendar.where(employer: @employer)

  def load_calendar
    @calendar = calendars.find(params[:id])
  end

  def busy_events(person, first, last)
    scope = LightekWorkspace::Event.scheduled.where(calendar_id: calendars.select(:id)).during(first, last)
    guest_events = LightekWorkspace::EventGuest.where(user: person).where.not(response: 'declined').select(:event_id)
    scope.where(organizer: person).or(scope.where(id: guest_events))
  end

  def notify(guest, event, title)
    return unless defined?(DymondDash::Notification)

    DymondDash::Notification.create!(recipient: guest, subject: event, category: 'system', title: title,
      url: dashboard_shared_calendar_path(@calendar, employer_id: @employer.id, date: event.starts_at.to_date))
  end

  def back(date: params[:date].presence)
    redirect_to dashboard_shared_calendar_path(@calendar, employer_id: @employer.id, date: date), status: :see_other
  end
end
