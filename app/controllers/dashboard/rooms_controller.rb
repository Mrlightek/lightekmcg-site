class Dashboard::RoomsController < ApplicationController
  layout 'dymond_dash/layouts/dymond_dash'
  protect_from_forgery with: :exception
  before_action :load_site
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, LightekSessions::Access::Denied, with: :invalid_room
  def index
    @media_ready = LightekSessions::Media.configured?(@site)
    @rooms = LightekSessions::Room.joins(:resource).where(lightek_reservation_resources: {site_id: @site.id})
      .where('ends_at > ?', Time.current).where.not(status: 'ended').includes(:resource).order(:starts_at).limit(100)
    @rooms = @rooms.where(host_user_id: current_user.id) unless current_user.role == 'super_admin' || @site.tenant == current_user
    @creation = {}
  end
  def create
    @creation = params.require(:room).permit(:name, :kind, :capacity, :duration_minutes, :starts_at).to_h
    room = LightekSessions::RoomCreation.call(site: @site, actor: current_user, attributes: @creation)
    redirect_to session_room_path(room.key), status: :see_other, notice: 'Room created. Open it, invite your guests, then bring it into Live Studio.'
  end
  private
  def load_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name)
    @site = params[:site_id].present? ? @sites.find(params[:site_id]) : @sites.first
    render :no_application, status: (action_name == 'index' ? :ok : :unprocessable_entity) unless @site
  end
  def invalid_room(error)
    @error = error.message
    @media_ready = LightekSessions::Media.configured?(@site)
    @rooms = LightekSessions::Room.none
    render :index, status: :unprocessable_entity
  end
end
