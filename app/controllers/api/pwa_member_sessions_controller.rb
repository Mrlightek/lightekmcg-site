class Api::PwaMemberSessionsController < Api::ReservationFederationController
  rescue_from LightekPwa::Policy::Denied do |e|
    render json: {error: e.message}, status: :forbidden
  end
  def create
    render json: LightekPwa::MemberBackends.redeem_ticket!(peer: @peer, token: params.require(:ticket))
  end
end
