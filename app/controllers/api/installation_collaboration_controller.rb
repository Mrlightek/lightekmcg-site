# frozen_string_literal: true

class Api::InstallationCollaborationController < Api::ReservationFederationController
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: {error: 'Installation resource unavailable.'}, status: :not_found }
  rescue_from LightekPeople::Access::Denied, with: -> { render json: {error: 'Installation access denied.'}, status: :forbidden }
  rescue_from LightekEmailProvisioningService::Unavailable, LightekMail::Submission::Unavailable,
    with: ->(error) { render json: {error: error.message}, status: :service_unavailable }

  def team
    service = LightekTeam::Network.new(peer: @peer, subject: params.require(:subject), actor_name: params.require(:actor_name))
    key = params[:key]
    result = case params[:operation]
    when 'list' then service.list
    when 'create' then service.create!(name: params.require(:name), address: params.require(:address))
    when 'show' then service.show(key, before: params[:before])
    when 'accept' then service.accept!(key)
    when 'disconnect' then service.disconnect!(key)
    when 'member' then service.member!(key, subject: params.require(:member_subject), display_name: params[:display_name], remove: params[:remove] == true)
    when 'post' then service.post!(key, body: params.require(:body), request_key: params.require(:request_key))
    end
    render json: result
  end

  def office
    return head :payload_too_large if request.content_length.to_i > 400.kilobytes

    network = LightekTeam::Network.new(peer: @peer, subject: params.require(:subject), actor_name: params.require(:actor_name))
    values = params.permit(:file_key, :kind, :title, :content, :lock_version).to_h
    render json: network.office!(params.require(:key), params.require(:operation), values)
  end

  def mail
    raise LightekPeople::Access::Denied unless params[:subject] == 'owner'

    service = LightekMail::InstallationMailbox.new(@peer)
    result = case params[:operation]
    when 'provision' then {address: service.provision!.address}
    when 'inbox' then service.inbox(params.fetch(:folder, 'inbox'))
    when 'read' then service.read(params.require(:id))
    when 'send' then service.send!(params.permit(:to, :subject_line, :text, :request_key).to_h.transform_keys { |key| key == 'subject_line' ? 'subject' : key })
    end
    render json: result
  end
end
