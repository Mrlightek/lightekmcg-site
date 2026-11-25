# frozen_string_literal: true

require "socket"
require "timeout"

module ItServices
  class RemoteSupportFileScanner
    class Unavailable < StandardError; end

    def self.port
      number = Integer(Rails.application.credentials.dig(:it_remote_support, :clamd_port), exception: false)
      number if number&.between?(1, 65_535)
    end

    def self.clean?(bytes)
      configured_port = port
      raise Unavailable unless configured_port

      response = Timeout.timeout(8) do
        Socket.tcp("127.0.0.1", configured_port, connect_timeout: 2) do |socket|
          socket.write("zINSTREAM\0")
          socket.write([bytes.bytesize].pack("N"))
          socket.write(bytes)
          socket.write([0].pack("N"))
          socket.gets("\0", 1024)
        end
      end
      return true if response == "stream: OK\0"
      return false if response&.end_with?(" FOUND\0")

      raise Unavailable
    rescue SystemCallError, IOError, Timeout::Error
      raise Unavailable
    end
  end
end
