class SessionRoomsController < ApplicationController
  skip_authorization_check
  protect_from_forgery with: :exception
  layout 'reservations'
  before_action { response.headers['Cache-Control'] = 'private, no-store'; response.headers['Referrer-Policy'] = 'same-origin' }
  before_action :load_room, except: :from_reservation
  rescue_from LightekSessions::Access::Denied, with: :denied
  rescue_from LightekSessions::Media::Unavailable, with: :unavailable
  def from_reservation
    booking = LightekReservations::Reservation.find(params.require(:reservation_id))
    raise LightekSessions::Access::Denied, 'This reservation belongs to another account.' unless booking.customer == current_user ||
      booking.resource.site.tenant == current_user || current_user.role == 'super_admin'
    raise LightekSessions::Access::Denied, 'Confirm this reservation before joining.' unless booking.access_ready?
    room = LightekSessions::Room.for_reservation!(booking)
    redirect_to session_room_path(room.key), status: :see_other
  end
  def show
    @site = @room.resource.site
    @host = @room.host?(current_user)
  end
  def state
    member = LightekSessions::Access.request!(@room, current_user)
    members = @room.members.where('last_seen_at > ?', 60.seconds.ago).includes(:user)
    render json: {status: @room.status, locked: @room.locked, admitted: member.status == 'admitted',
      ends_at: @room.ends_at.iso8601, presentation: @room.presentation, broadcast_consent: @room.broadcast_consent,
      members: @room.host?(current_user) ? members.map { |m| {id: m.id, name: m.user.first_name, status: m.status} } : []}
  end
  def ticket
    raise LightekSessions::Access::Denied, 'Accept that the host can broadcast this session before joining.' unless params[:consent] == true
    LightekSessions::Access.request!(@room, current_user)
    render json: LightekSessions::Media.new(@room.resource.site).join!(@room, current_user, studio: params[:studio] == true)
  end
  def control
    LightekSessions::Access.host!(@room, current_user)
    removed_member = nil
    @room.with_lock do
      LightekSessions::Access.authorize!(@room, current_user)
      case params.require(:operation)
      when 'open'
        raise LightekSessions::Access::Denied, 'The room opens 15 minutes before its start.' if Time.current < @room.starts_at - 15.minutes
        @room.update!(status: 'open')
        LightekSessions::CloseRoomJob.set(wait_until: @room.ends_at).perform_later(@room.id)
      when 'lock' then @room.update!(locked: true)
      when 'unlock' then @room.update!(locked: false)
      when 'end'
        @room.update!(status: 'ended')
        LightekSessions::CloseRoomJob.perform_later(@room.id)
      when 'admit', 'remove'
        member = @room.members.find(params.require(:member_id))
        raise LightekSessions::Access::Denied, 'The host cannot be removed.' if @room.host?(member.user)
        if params[:operation] == 'admit'
          LightekSessions::Access.eligible_member!(@room, member)
          member.update!(status: 'admitted')
        else
          member.update!(status: 'blocked')
          removed_member = member
        end
      when 'mute'
        member = @room.members.find(params.require(:member_id))
        media = LightekSessions::Media.new(@room.resource.site)
        info = media.call('ListParticipants', {room: @room.media_name}, room: @room.media_name)
        participant = info.fetch('participants', []).find { |p| p['identity'] == "user-#{member.user_id}" }
        Array(participant&.fetch('tracks', [])).select { |track| track['source'] == 'MICROPHONE' || track['source'] == 2 }.each do |track|
          media.call('MutePublishedTrack', {room: @room.media_name, identity: participant.fetch('identity'), track_sid: track.fetch('sid'), muted: true}, room: @room.media_name)
        end
      else raise LightekSessions::Access::Denied, 'Unknown room control.'
      end
    end
    if removed_member
      LightekSessions::Media.new(@room.resource.site).call('RemoveParticipant', {room: @room.media_name, identity: "user-#{removed_member.user_id}"}, room: @room.media_name)
    end
    render json: {status: @room.status}
  end
  def presentation
    LightekSessions::Access.host!(@room, current_user)
    values = params.require(:presentation).permit(:layout, :title, :subtitle, :ticker, :brand, :featured, :background, :accent, participants: {}).to_h
    @room.update!(presentation: LightekSessions::Presentation.normalize!(values))
    render json: {presentation: @room.presentation}
  rescue ArgumentError => error
    render json: {error: error.message}, status: :unprocessable_entity
  end
  def invite
    member = LightekSessions::Access.invite!(@room, current_user, params.require(:email_address))
    render json: {message: 'Place assigned. Ask your guest to sign in and open this room link.', room_path: session_room_path(@room.key)}, status: :created
  end
  private
  def load_room
    @room = LightekSessions::Room.find_by!(key: params[:key])
    LightekSessions::Access.authorize!(@room, current_user)
  end
  def denied(error) = render(json: {error: error.message}, status: :forbidden)
  def unavailable(error) = render(json: {error: error.message}, status: :service_unavailable)
end
