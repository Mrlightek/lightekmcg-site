# app/services/port_listener.rb
require "socket"

class PortListener
  def initialize(port:, protocol:, receiver:)
    @port = port
    @protocol = protocol.to_s.downcase
    @receiver = receiver
    @running = false
  end

  def start
    return self if @running
    @running = true

    case @protocol
    when "tcp" then start_tcp_listener
    when "udp" then start_udp_listener
    else raise ArgumentError, "Unsupported listener protocol: #{@protocol}"
    end

    self
  end

  def stop
    @running = false
    @server&.close
    @thread&.kill
    self
  end

  private

  def start_tcp_listener
    @server = TCPServer.new("0.0.0.0", @port)
    @thread = Thread.new do
      while @running
        begin
          socket = @server.accept
          Thread.new(socket) { |client| handle_tcp_connection(client) }
        rescue IOError, Errno::EBADF
          break unless @running
        end
      end
    end
  end

  def handle_tcp_connection(client)
    remote_ip = client.peeraddr[3] rescue nil
    payload = ""

    # Safely read full stream until client closes or finishes frame
    while (chunk = client.readpartial(4096) rescue nil)
      payload << chunk
      break if payload.bytesize > 10_000_000 # 10MB safety cap
    end

    connection = Connection.new(
      local_port: @port,
      protocol: @protocol,
      payload: payload,
      socket: client,
      remote_ip: remote_ip
    )

    # Clean up DB connections inside worker threads
    ActiveRecord::Base.connection_pool.with_connection do
      @receiver.call(connection)
    end
  ensure
    client.close unless client.closed?
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
          ActiveRecord::Base.connection_pool.with_connection do
            @receiver.call(connection)
          end
        rescue IOError, Errno::EBADF
          break unless @running
        end
      end
    end
  end

  Connection = Struct.new(:local_port, :protocol, :payload, :socket, :remote_ip, keyword_init: true)
end