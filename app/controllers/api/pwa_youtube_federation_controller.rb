class Api::PwaYoutubeFederationController < Api::ReservationFederationController
  rescue_from LightekPwa::Policy::Denied do |e|
    render json: {error: e.message}, status: :forbidden
  end
  rescue_from LightekPwa::YoutubePublishing::Unavailable do |e|
    render json: {error: e.message}, status: :unprocessable_entity
  end
  def create
    if params[:withdraw] == true
      upload = LightekPwa::YoutubeUpload.find_by(peer: @peer, source_post_id: params.require(:source_post_id))
      return render json: {status: 'withdrawn'} unless upload
      LightekPwa::YoutubePublishing.request_withdrawal!(upload)
      return render json: upload.summary
    end
    payload = params.permit(:source_post_id, :title, :description, :byte_size, :checksum, :content_type, :source_grant, :consent, :made_for_kids).to_h
    render json: LightekPwa::YoutubePublishing.accept!(peer: @peer, payload: payload).summary
  end
  def show
    render json: LightekPwa::YoutubeUpload.where(peer: @peer).find_by!(public_key: params.require(:key)).summary
  end
end
