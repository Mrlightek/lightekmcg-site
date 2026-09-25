require "open3"

module Gatekeeper
  class CommandRunner
    Result = Data.define(:command, :stdout, :stderr, :exit_status) do
      def success? = exit_status.to_i.zero?
      def output = [stdout, stderr].reject(&:blank?).join("\n")
    end

    def self.call(node:, command:)
      node.local? ? local(command) : remote(node, command)
    end

    def self.local(command)
      stdout, stderr, status = Open3.capture3(command)
      Result.new(command:, stdout:, stderr:, exit_status: status.exitstatus)
    end
    private_class_method :local

    def self.remote(node, command)
      require "net/ssh"

      stdout = +""
      stderr = +""
      exit_status = 255

      options = {
        port: node.ssh_port,
        non_interactive: true,
        verify_host_key: :accept_new
      }
      options[:keys] = [node.ssh_key_path] if node.ssh_key_path.present?

      Net::SSH.start(node.ip_address, node.ssh_user, **options) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(command) do |_channel, success|
            raise "SSH command could not be started" unless success
            ch.on_data { |_c, data| stdout << data }
            ch.on_extended_data { |_c, _type, data| stderr << data }
            ch.on_request("exit-status") { |_c, data| exit_status = data.read_long }
          end
        end
        channel.wait
      end

      Result.new(command:, stdout:, stderr:, exit_status:)
    end
    private_class_method :remote
  end
end
