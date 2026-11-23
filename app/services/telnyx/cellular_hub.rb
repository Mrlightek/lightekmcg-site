# frozen_string_literal: true

require "net/ssh"
require "timeout"
require "shellwords"

module Telnyx
  class CellularHub
    class Error < StandardError; end

    SCRIPT = "/usr/local/bin/add_user_route.sh"

    def check_peer!(peer_ip)
      raise Error, "Invalid customer WireGuard peer" unless UserEsim.host_ipv4?(peer_ip)
      execute!("--check", peer_ip)
    end

    def check_connected_peer!(peer_ip)
      raise Error, "Invalid customer WireGuard peer" unless UserEsim.host_ipv4?(peer_ip)
      execute!("--check-connected", peer_ip)
    end

    def install!(ip, peer_ip, table)
      unless UserEsim.host_ipv4?(ip) && UserEsim.host_ipv4?(peer_ip) && table.is_a?(Integer) &&
          table.between?(100, 2_147_483_647) && !(253..255).cover?(table)
        raise Error, "Invalid cellular policy route"
      end

      execute!(ip, peer_ip, table.to_s)
    end

    private

    def execute!(*arguments)
      command = Shellwords.join(["sudo", "-n", SCRIPT, *arguments])
      status = nil
      accepted = false
      Timeout.timeout(25) do
        Net::SSH.start(ENV.fetch("HUB_VPS_HOST"), ENV.fetch("HUB_VPS_USER"), {
          key_data: [ENV.fetch("HUB_VPS_SSH_KEY")], keys_only: true, auth_methods: ["publickey"],
          non_interactive: true, verify_host_key: :always,
          user_known_hosts_file: [ENV.fetch("HUB_VPS_KNOWN_HOSTS_FILE")],
          global_known_hosts_file: [], timeout: 8
        }) do |ssh|
          ssh.open_channel do |channel|
            channel.exec(command) do |ch, success|
              accepted = success
              ch.on_request("exit-status") { |_channel, data| status = data.read_long }
            end
          end
          ssh.loop
        end
      end
      raise Error, "Hub route command failed (exit #{status || 'unknown'})" unless accepted && status == 0
    rescue Net::SSH::Exception, Timeout::Error, IOError, SystemCallError, SocketError, EOFError
      raise Error, "Hub SSH session could not be confirmed", cause: nil
    end
  end
end
