# app/controllers/concerns/network_controller.rb

module NetworkController
  extend ActiveSupport::Concern

  def web_hook(
    port:,
    protocol:,
    payload: nil,
    socket: nil,
    source_ip: nil,
    metadata: {}
  )
    case protocol.to_s.downcase
    when "smtp"
      handle_smtp(
        port: port,
        payload: payload,
        socket: socket,
        source_ip: source_ip
      )

    when "ssh"
      handle_ssh(
        port: port,
        socket: socket,
        source_ip: source_ip
      )

    when "tcp"
      handle_tcp(
        port: port,
        payload: payload,
        socket: socket,
        source_ip: source_ip
      )

    when "udp"
      handle_udp(
        port: port,
        payload: payload,
        source_ip: source_ip
      )

    when "http", "https"
      handle_http(
        port: port,
        payload: payload,
        source_ip: source_ip,
        metadata: metadata
      )

    else
      {
        routed: false,
        error: "Unsupported protocol",
        protocol: protocol,
        port: port
      }
    end
  end

  def outbound(
  host:,
  port:,
  protocol:,
  payload: nil,
  metadata: {}
)
  case protocol.to_s.downcase
    when "event", "rtm", "push"
  handle_event(
    payload: payload,
    source_ip: source_ip,
    metadata: metadata
  )

  when "smtp"
    outbound_smtp(
      host: host,
      port: port,
      payload: payload,
      metadata: metadata
    )

  when "ssh"
    outbound_ssh(
      host: host,
      port: port,
      payload: payload,
      metadata: metadata
    )

  when "tcp"
    outbound_tcp(
      host: host,
      port: port,
      payload: payload
    )

  when "udp"
    outbound_udp(
      host: host,
      port: port,
      payload: payload
    )

  when "http", "https"
    outbound_http(
      host: host,
      port: port,
      protocol: protocol,
      payload: payload,
      metadata: metadata
    )

  else
    {
      sent: false,
      error: "Unsupported outbound protocol",
      protocol: protocol,
      host: host,
      port: port
    }
  end
end

  private

  #Event handeler
  def handle_event(payload:, source_ip:, metadata:)
  event_name =
    metadata[:event_name] ||
    metadata["event_name"]

  event = NetworkEvent.enabled.find_by(
    name: event_name
  )

  unless event
    return {
      routed: false,
      type: "event",
      event: event_name,
      error: "Event is not registered"
    }
  end

  route_connection(
    protocol: :event,
    payload: payload,
    source_ip: source_ip,

    metadata: metadata.merge(
      event_id: event.id,
      event_name: event.name,
      source: event.source,
      destination: event.destination,
      transport: event.transport
    )
  )
end

#For SMTP:
  def outbound_smtp(
  host:,
  port:,
  payload:,
  metadata:
)
  require "net/smtp"

  from = metadata.fetch(:from)
  recipients = Array(metadata.fetch(:to))

  Net::SMTP.start(host, port) do |smtp|
    smtp.send_message(
      payload.to_s,
      from,
      recipients
    )
  end

  {
    sent: true,
    protocol: "smtp",
    host: host,
    port: port,
    recipients: recipients
  }
end

#For HTTP/HTTPS:
  def outbound_http(
  host:,
  port:,
  protocol:,
  payload:,
  metadata:
)
  require "net/http"

  path = metadata[:path] || "/"

  uri = URI(
    "#{protocol}://#{host}:#{port}#{path}"
  )

  request = Net::HTTP::Post.new(uri)

  metadata.fetch(:headers, {}).each do |key, value|
    request[key] = value
  end

  request.body = payload.to_s

  response = Net::HTTP.start(
    uri.host,
    uri.port,
    use_ssl: protocol.to_s == "https"
  ) do |http|
    http.request(request)
  end

  {
    sent: true,
    protocol: protocol,
    host: host,
    port: port,
    status: response.code.to_i,
    body: response.body
  }
end

#For UDP:
  def outbound_udp(host:, port:, payload:)
  socket = UDPSocket.new

  socket.send(
    payload.to_s,
    0,
    host,
    port
  )

  {
    sent: true,
    protocol: "udp",
    host: host,
    port: port,
    bytes_sent: payload.to_s.bytesize
  }
ensure
  socket&.close
end

#For raw TCP:
  def outbound_tcp(host:, port:, payload:)
  socket = TCPSocket.new(host, port)

  socket.write(payload.to_s)

  {
    sent: true,
    protocol: "tcp",
    host: host,
    port: port,
    bytes_sent: payload.to_s.bytesize
  }
ensure
  socket&.close
end

def handle_smtp(port:, payload:, socket:, source_ip:)
    # Parse SMTP transaction.
    # Persist message.
    # Trigger mail-processing jobs.
    # Route to local mailbox if appropriate.

    {
      routed: true,
      handler: "smtp",
      port: port,
      source_ip: source_ip
    }
  end

  def handle_ssh(port:, socket:, source_ip:)
    # Decide which destination node/service owns this connection.
    # Forward/proxy socket rather than interpreting SSH in Rails.

    {
      routed: true,
      handler: "ssh",
      port: port,
      source_ip: source_ip
    }
  end

  def handle_tcp(port:, payload:, socket:, source_ip:)
    route_connection(
      protocol: :tcp,
      port: port,
      socket: socket,
      payload: payload,
      source_ip: source_ip
    )
  end

  def handle_udp(port:, payload:, source_ip:)
    route_connection(
      protocol: :udp,
      port: port,
      payload: payload,
      source_ip: source_ip
    )
  end

  def handle_http(port:, payload:, source_ip:, metadata:)
    route_connection(
      protocol: :http,
      port: port,
      payload: payload,
      source_ip: source_ip,
      metadata: metadata
    )
  end

  def route_connection(**connection)
    # Look up destination by:
    # port
    # protocol
    # host
    # service
    # tenant
    # destination IP
    # etc.

    connection.merge(
      routed: true
    )
  end
end