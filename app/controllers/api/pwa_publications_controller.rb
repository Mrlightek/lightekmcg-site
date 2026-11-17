class Api::PwaPublicationsController < Api::ReservationFederationController
  rescue_from LightekPwa::Policy::Denied do |e|
    render json: {error: e.message}, status: :forbidden
  end
  def create
    values = params.permit(:remote_post_id, :revision, :removed, :title, :kind, :expires_at, :youtube_video_id).to_h
    ref = LightekPwa::Publications.accept!(peer: @peer, payload: values)
    render json: {reference_id: ref.id, revision: ref.revision, removed: ref.removed?}
  end
end
