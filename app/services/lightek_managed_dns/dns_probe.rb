require "resolv"
require "securerandom"
require "socket"
require "timeout"

module LightekManagedDns
  module DnsProbe
    class Unavailable < StandardError; end

    def self.answers(address, name, resource, port: 53)
      query = Resolv::DNS::Message.new(SecureRandom.random_number(65_536))
      query.add_question(name, resource)
      data = query.encode
      reply = Timeout.timeout(3) do
        Socket.tcp(address, port, connect_timeout: 2) do |socket|
          socket.write([data.bytesize].pack("n") + data)
          length = socket.read(2)
          raise Unavailable unless length&.bytesize == 2
          packet = socket.read(length.unpack1("n"))
          Resolv::DNS::Message.decode(packet || "")
        end
      end
      unless reply.id == query.id && reply.qr == 1 && reply.aa == 1 && reply.tc == 0 && reply.rcode == 0 && reply.question == query.question
        raise Unavailable
      end

      reply.answer.filter_map { |owner, _, value| value if owner.to_s.casecmp?(name.delete_suffix(".")) && value.instance_of?(resource) }
    rescue IOError, SocketError, SystemCallError, Timeout::Error, Resolv::DNS::DecodeError
      raise Unavailable
    end
  end
end
