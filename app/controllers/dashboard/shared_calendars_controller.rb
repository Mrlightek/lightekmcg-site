class Dashboard::SharedCalendarsController < Dashboard::SharedWorkspaceController
  before_action :load_calendar, except: %i[index create]
  rescue_from ActiveRecord::RecordInvalid, ArgumentError, LightekSessions::Access::Denied, LightekMail::Access::Denied do |error|
    redirect_to(@calendar ? dashboard_shared_calendar_path(@calendar, employer_id: @employer.id, date: (params[:date] unless action_name == 'show')) : dashboard_shared_calendars_path(employer_id: @employer.id),
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
    @events = @calendar.events.scheduled.during(first, last).includes(:organizer, :session_room, guests: :user).order(:starts_at, :id).limit(150)
    if @events.any? { |event| !event.session_room_id? && event.starts_at.future? && can_manage_event?(event) }
      @meeting_sites = meeting_sites.order(:name, :id).limit(100)
    end
    cancelled = @calendar.events.where.not(cancelled_at: nil).during(first, last)
    cancelled = cancelled.where(organizer: current_user) unless @owner
    @cancelled_with_invitations = cancelled.where(id: LightekWorkspace::ExternalInvitation.select(:event_id)).order(:starts_at, :id).limit(150)
    managed_ids = @events.select { |event| can_manage_event?(event) }.map(&:id) + @cancelled_with_invitations.map(&:id)
    @external_invitations = LightekWorkspace::ExternalInvitation.where(event_id: managed_ids).includes(:message).order(:attendee_address).group_by(&:event_id)
    @sending_mailboxes = owned_mailboxes if @events.any? { |event| event.ends_at.future? && can_manage_event?(event) }
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

  def invite_external
    event = @calendar.events.scheduled.find(params[:event_id])
    raise LightekPeople::Access::Denied unless can_manage_event?(event)

    mailbox = owned_mailboxes.find { |account| account.id.to_s == params.require(:mailbox_id) }
    raise ArgumentError, 'Choose an active Lightek Mail mailbox you own.' unless mailbox
    addresses = LightekMail::Submission.addresses(params.require(:attendee_address))
    unless addresses.one? && LightekWorkspace::CalendarInvitationMail::ADDRESS.match?(addresses.first) && addresses.first != mailbox.address
      raise ArgumentError, 'Enter one guest email address different from the organizer mailbox.'
    end

    event.with_lock do
      raise ActiveRecord::RecordNotFound if event.cancelled_at? || event.ends_at.past?

      invitations = event.external_invitations
      if invitations.exists?(attendee_address: addresses.first)
        raise ArgumentError, 'This guest already has an invitation.'
      end
      raise ArgumentError, 'Invite up to 50 external guests per event.' if invitations.count >= 50

      invitations.create!(mailbox: mailbox, organizer_address: mailbox.address,
        attendee_address: addresses.first, uid: "#{SecureRandom.uuid}@calendar.lightek").enqueue_delivery
    end
    back(date: params[:date].presence || event.starts_at.to_date, notice: 'Calendar invitation queued.')
  end

  def retry_external_invitation
    event = @calendar.events.find(params[:event_id])
    raise LightekPeople::Access::Denied unless can_manage_event?(event)

    event.with_lock do
      invitation = event.external_invitations.find(params[:invitation_id])
      if invitation.message&.state == 'failed'
        invitation.revise!
      elsif invitation.delivery_error? && !invitation.message_id?
        invitation.update!(delivery_error: nil)
        invitation.enqueue_delivery
      else
        raise ArgumentError, 'Only failed calendar deliveries can be retried here.'
      end
    end
    back(date: params[:date].presence || event.starts_at.to_date, notice: 'Calendar delivery queued.')
  end

  def add_meeting
    event = @calendar.events.scheduled.find(params[:event_id])
    raise LightekPeople::Access::Denied unless can_manage_event?(event)

    event.with_lock do
      raise ActiveRecord::RecordNotFound if event.cancelled_at?
      unless event.session_room_id?
        site = meeting_sites.find(params.require(:site_id))
        unless LightekSessions::Media.configured?(site)
          raise ArgumentError, 'Activate video meeting media for this website in Dashboard first.'
        end

        room = LightekSessions::RoomCreation.call(site: site, actor: current_user, attributes: {
          name: event.title, kind: 'video', starts_at: event.starts_at.iso8601,
          duration_minutes: event.meeting_duration_minutes, capacity: [event.guests.count, 1].max
        })
        guests = @workspace.roster.where(id: event.guests.select(:user_id)).to_a
        guests.each { |guest| room.members.create!(user: guest) unless room.host?(guest) }
        event.update!(session_room: room)
        guests.each { |guest| notify(guest, event, 'Video meeting added to your calendar event') }
      end
    end
    back(date: event.starts_at.to_date)
  end

  def reschedule
    event = @calendar.events.scheduled.find(params[:event_id])
    raise LightekPeople::Access::Denied unless can_manage_event?(event)

    values = params.require(:event).permit(:title, :details, :starts_at, :ends_at)
    event.with_lock do
      raise ActiveRecord::RecordNotFound if event.cancelled_at?

      event.update!(values)
      if event.saved_changes.keys.intersect?(%w[title details starts_at ends_at])
        event.external_invitations.each(&:revise!)
      end
      if event.saved_change_to_starts_at? || event.saved_change_to_ends_at?
        move_meeting!(event) if event.session_room_id?
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
    raise LightekPeople::Access::Denied unless can_manage_event?(event)

    live_room_ids = @calendar.with_lock do
      occurrences = if params[:scope] == 'following' && event.series_key?
        @calendar.events.scheduled.where(series_key: event.series_key).where('starts_at >= ?', event.starts_at)
      else
        @calendar.events.scheduled.where(id: event.id)
      end
      cancelled = occurrences.order(:id).lock.to_a
      rooms = cancelled.filter_map do |occurrence|
        occurrence.update!(cancelled_at: Time.current)
        occurrence.external_invitations.each(&:revise!)
        close_meeting!(occurrence.session_room)
      end
      if cancelled.any?
        recipients = LightekWorkspace::EventGuest.where(event_id: cancelled.map(&:id)).select(:user_id)
        label = cancelled.one? ? 'Shared calendar event cancelled' : 'Recurring calendar events cancelled'
        @workspace.roster.where(id: recipients).each { |guest| notify(guest, event, label) }
      end
      rooms
    end
    live_room_ids.each { |id| LightekSessions::CloseRoomJob.perform_later(id) }
    back
  end

  def ics
    event = @calendar.events.scheduled.find(params[:event_id])
    time = ->(value) { value.utc.strftime('%Y%m%dT%H%M%SZ') }
    uid = Digest::SHA256.hexdigest([request.host, event.id, event.created_at.to_i].join(':'))
    lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Lightek//Shared Calendar//EN', 'BEGIN:VEVENT',
      "UID:#{uid}@lightek", "DTSTAMP:#{time.call(event.updated_at)}", "DTSTART:#{time.call(event.starts_at)}",
      "DTEND:#{time.call(event.ends_at)}", "SUMMARY:#{LightekSales::TaskCalendar.escape(event.title)}",
      "DESCRIPTION:#{LightekSales::TaskCalendar.escape(event.details)}"]
    if event.meeting_link_available_to?(current_user)
      lines << "URL:#{session_room_url(event.session_room.key)}"
    end
    lines.concat(['END:VEVENT', 'END:VCALENDAR'])
    send_data lines.map { |line| LightekSales::TaskCalendar.fold(line) }.join("\r\n") + "\r\n",
      filename: 'shared-event.ics', type: 'text/calendar', disposition: 'attachment'
  end

  private

  def can_manage_event?(event)
    @owner || event.organizer_id == current_user.id
  end
  helper_method :can_manage_event?

  def owned_mailboxes
    LightekMail::Access.accounts(current_user).where(user: current_user, enabled: true).includes(:domain).order(:address).select(&:sending_ready?)
  rescue LightekMail::Access::Denied
    []
  end

  def meeting_sites
    LightekSettings::WebsiteIdentity.sites_for(current_user).where(tenant: @employer)
  end

  def move_meeting!(event)
    room = event.session_room
    room.with_lock do
      unless room.status == 'scheduled' && room.starts_at.future? && event.starts_at.future?
        raise ArgumentError, 'A video meeting can only be rescheduled before it starts.'
      end

      room.resource.update!(duration_minutes: event.meeting_duration_minutes)
      room.update!(starts_at: event.starts_at, ends_at: event.ends_at)
    end
  end

  def close_meeting!(room)
    return unless room

    room.with_lock do
      was_open = room.status == 'open'
      room.update!(status: 'ended') unless room.status == 'ended'
      room.id if was_open
    end
  end

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

  def back(date: params[:date].presence, notice: nil)
    redirect_to dashboard_shared_calendar_path(@calendar, employer_id: @employer.id, date: date), status: :see_other, notice: notice
  end
end
