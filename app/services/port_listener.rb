# app/services/port_listener.rb

require "socket"

class PortListener
  def initialize(port:, protocol:, receiver:)
    @port = port
    @protocol = protocol.to_s.downcase
    @receiver = receiver
    @server = nil
    @thread = nil
    @running = false
  end

  def start
    return self if @running

    @running = true

    case @protocol
    when "tcp", "smtp", "ssh", "http", "https"
      start_tcp_listener

    when "udp"
      start_udp_listener

    else
      raise ArgumentError, "Unsupported listener protocol: #{@protocol}"
    end

    self
  end

  def stop
    @running = false
    @server&.close
    @thread&.kill
    @thread = nil
    @server = nil

    self
  end

  private

  def start_tcp_listener
    @server = TCPServer.new("0.0.0.0", @port)

    @thread = Thread.new do
      while @running
        begin
          socket = @server.accept

          Thread.new(socket) do |client|
            handle_tcp_connection(client)
          end

        rescue IOError, Errno::EBADF
          break unless @running
        end
      end
    end
  end

  def start_udp_listener
    @server = UDPSocket.new
    @server.bind("0.0.0.0", @port)

    @thread = Thread.new do
      while @running
        begin
          payload, sender = @server.recvfrom(65_535)

          connection = Connection.new(
            local_port: @port,
            protocol: @protocol,
            payload: payload,
            socket: @server,
            remote_ip: sender[3]
          )

          @receiver.call(connection)

        rescue IOError, Errno::EBADF
          break unless @running
        end
      end
    end
  end

  def handle_tcp_connection(client)
    remote_ip =
      begin
        client.peeraddr[3]
      rescue StandardError
        nil
      end

    payload =
      begin
        client.readpartial(65_535)
      rescue EOFError
        nil
      end

    connection = Connection.new(
      local_port: @port,
      protocol: @protocol,
      payload: payload,
      socket: client,
      remote_ip: remote_ip
    )

    @receiver.call(connection)
  ensure
    client.close unless client.closed?
  end

  Connection = Struct.new(
    :local_port,
    :protocol,
    :payload,
    :socket,
    :remote_ip,
    keyword_init: true
  )
end