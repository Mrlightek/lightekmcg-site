require "open3"

module Gatekeeper
  class FirewallService
    class CommandError < StandardError; end
    HELPER = ENV.fetch("LIGHTEK_FIREWALL_HELPER", "/usr/local/sbin/lightek-firewall-control").freeze

    def status = run!("status")
    def open!(port:, protocol: "tcp") = mutate!("open", port, protocol)
    def close!(port:, protocol: "tcp") = mutate!("close", port, protocol)

    private

    def mutate!(action, port, protocol)
      port = Integer(port)
      protocol = protocol.to_s.downcase
      raise ArgumentError, "Port must be 1-65535" unless port.between?(1,65535)
      raise ArgumentError, "Protocol must be tcp or udp" unless %w[tcp udp].include?(protocol)
      run!(action, port.to_s, protocol)
    end

    def run!(*args)
      stdout, stderr, status = Open3.capture3("sudo", "-n", HELPER, *args)
      raise CommandError, stderr.presence || stdout.presence || "Firewall command failed" unless status.success?
      stdout
    end
  end
end
