class StudioAudienceChannel < ApplicationCable::Channel
  def subscribed
    Gatekeeper::StudioLivePolicy.authorize!(user: current_user)
    data = Rails.application.message_verifier('studio_audience').verified(params[:ticket].to_s, purpose: 'audience_reader')
    raise ArgumentError, 'Audience connection expired. Reconnect from Studio.' unless data && data['user_id'].to_s == current_user.id.to_s && %w[tiktok ssn].include?(data['source'])
    source = data.fetch('source')
    settings = Studio::Live::Audience.settings(current_user)
    config = source == 'tiktok' ? {'source'=>source, 'username'=>settings.fetch('tiktok_username')} : {'source'=>source, 'session'=>settings.fetch('ssn_session')}
    config['sign_api_key'] = settings['sign_api_key'] if source == 'tiktok' && settings['sign_api_key'].present?
    @lease = LightekAudienceLease.acquire!(current_user, source)
    @reader = Studio::Live::SocialReader.new(config) do |event|
      if event['type'] == 'status' && event['status'] == 'reader_stopped'
        ActiveRecord::Base.connection_pool.with_connection { LightekAudienceLease.where(id: @lease.id).delete_all }
      end
      transmit(event)
    end
  rescue StandardError
    @lease&.destroy
    transmit({'type'=>'status', 'status'=>'unavailable'})
    reject
  ensure
    config&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
  end
  def heartbeat(_ = {})
    Gatekeeper::StudioLivePolicy.authorize!(user: current_user.reload)
    raise ArgumentError unless @lease && LightekAudienceLease.where(id: @lease.id).where('expires_at > ?', Time.current).update_all(expires_at: 60.seconds.from_now) == 1
    @reader&.heartbeat
  rescue StandardError
    @reader&.stop
    stop_all_streams
    transmit({'type'=>'status', 'status'=>'expired'})
  end
  def unsubscribed
    @reader&.stop
    @lease&.destroy
  end
  private
  def logger = (@silent_logger ||= ActiveSupport::Logger.new(File::NULL))
end
