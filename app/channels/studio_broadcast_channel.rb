# frozen_string_literal: true
class StudioBroadcastChannel < ApplicationCable::Channel
  def subscribed
    @operation = Studio::Live::Sessions.from_ticket!(params[:ticket], current_user)
    @last_heartbeat = Time.current
    Rails.logger.info("[StudioLive] subscribed operation=#{@operation.id} user=#{current_user.id}")
  rescue ::Gatekeeper::StudioLivePolicy::Denied, ActiveRecord::RecordNotFound
    Rails.logger.info("[StudioLive] subscription rejected")
    reject
  rescue StandardError => error
    Rails.logger.error("[StudioLive] subscription failed class=#{error.class.name}")
    reject
  end
  def start(_data = {})
    ::Gatekeeper::StudioLivePolicy.authorize!(user: current_user.reload, operation: @operation)
    @operation.with_lock do
      raise Studio::Live::Encoder::Failure, "This session was already started. Start a new session." unless @operation.status == "draft"
      @operation.update!(status: "connecting")
      @claimed = true
    end
    Rails.logger.info("[StudioLive] encoder starting operation=#{@operation.id} user=#{current_user.id}")
    test = @operation.metadata["destination"] == "test"
    output = test ? Studio::Live::Encoder.recording_path(@operation.id) : Studio::Live::Destination.output!(current_user)
    @encoder = Studio::Live::Encoder.new(output: output, test: test, on_event: method(:encoder_event)).start!
    transmit({event: "ready"})
  rescue StandardError => error
    fail_session(error)
  end
  def chunk(data)
    raise Studio::Live::Encoder::Failure, "Start a new broadcast session." unless @encoder
    sequence = @encoder.append!(encoded: data["live_chunk"], sequence: data["sequence"])
    heartbeat
    transmit({event: "ack", sequence: sequence})
  rescue StandardError => error
    fail_session(error)
  end
  def stop(_data = {})
    @encoder&.stop!
    unless @encoder
      Studio::Live::Sessions.scope.where(id: @operation.id, status: "draft").update_all(status: "cancelled", ended_at: Time.current) if @operation
    end
  end
  def heartbeat(_data = {})
    return unless @operation && Time.current - @last_heartbeat >= 5
    ::Gatekeeper::StudioLivePolicy.authorize!(user: current_user.reload, operation: @operation)
    Studio::Live::Sessions.scope.where(id: @operation.id, status: %w[draft connecting live]).update_all(updated_at: Time.current)
    @last_heartbeat = Time.current
  rescue ::Gatekeeper::StudioLivePolicy::Denied => error
    fail_session(error)
  end
  def unsubscribed
    stop
  end
  private
  # Action Cable's debug action/transmit logger must never print media chunks or tickets.
  def logger
    @silent_logger ||= ActiveSupport::Logger.new(File::NULL)
  end
  def encoder_event(event, error)
    ActiveRecord::Base.connection_pool.with_connection do
      Studio::Live::Sessions.event!(@operation, event, error)
    end
    transmit({event: event, error: error, download_url: event == "ended" && @operation.metadata["destination"] == "test" ? "/dashboard/live/#{@operation.id}/recording" : nil})
  end
  def fail_session(error)
    public_error = case error
    when Studio::Live::Encoder::Failure, Studio::Live::Destination::Unavailable, ::Gatekeeper::StudioLivePolicy::Denied then error.message
    else "The broadcast could not continue. Check server configuration and start a new session."
    end
    Studio::Live::Sessions.event!(@operation, "failed", public_error) if @operation && @claimed
    @encoder&.stop!(failure: public_error)
    transmit({event: "failed", error: public_error})
  end
end
