# app/services/network_listener.rb

class NetworkListener
  include NetworkController

  def receive(connection)
    web_hook(
      port: connection.local_port,
      protocol: connection.protocol,
      payload: connection.payload,
      socket: connection.socket,
      source_ip: connection.remote_ip
    )
  end

  def send_message(
    host:,
    port:,
    protocol:,
    payload:,
    metadata: {}
  )
    outbound(
      host: host,
      port: port,
      protocol: protocol,
      payload: payload,
      metadata: metadata
    )
  end

  def start
    listeners.each(&:start)
  end

  def stop
    listeners.each(&:stop)
  end

  private

  def listeners
    @listeners ||= build_listeners
  end

  def build_listeners
    network_listeners + event_listeners
  end

  def network_listeners
  NetworkPort.enabled.map do |network_port|
    PortListener.new(
      port: network_port.port,
      protocol: network_port.protocol,
      receiver: method(:receive)
    )
  end
end

def event_listeners
  NetworkEvent.enabled.map do |network_event|
    EventListener.new(
      event: network_event.event_name,
      receiver: method(:receive_event)
    )
  end
end
end