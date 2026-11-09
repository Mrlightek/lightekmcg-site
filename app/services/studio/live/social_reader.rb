require 'open3'
module Studio
  module Live
    class SocialReader
      def initialize(config, &receiver)
        path = Rails.root.join('tmp/live-audience-image')
        raise ArgumentError, 'Deploy the managed audience reader before connecting social chat.' unless path.file?
        image = path.read.strip
        raise ArgumentError, 'Invalid managed audience image.' unless image.match?(/\Alightek\/live-audience:[a-f0-9]{20}\z/)
        @input, @output, @waiter = Open3.popen2('docker', 'run', '--rm', '--init', '--read-only', '--memory=256m', '--cpus=0.5',
          '--pids-limit=64', '--cap-drop=ALL', '--security-opt=no-new-privileges', '-i', image, err: File::NULL)
        @input.puts(JSON.generate(config)); @input.flush
        @thread = Thread.new do
          begin
            @output.each_line do |line|
              break if line.bytesize > 8192
              event = JSON.parse(line)
              receiver.call(event) if event.is_a?(Hash) && %w[status chat member viewers gift like social activity].include?(event['type'])
            end
          rescue IOError, JSON::ParserError
            # Only normalized events leave the process; no upstream debug payloads.
          ensure
            receiver.call({'type'=>'status', 'status'=>'reader_stopped'})
          end
        end
      end
      def heartbeat
        @input.puts('{"type":"heartbeat"}'); @input.flush
      rescue IOError, Errno::EPIPE
        nil
      end
      def stop
        @input&.close rescue nil
        # EOF reaches the container's stdin and the bridge closes its own sockets.
        @output&.close rescue nil
        @thread&.join(1)
        @thread&.kill if @thread&.alive?
      end
    end
  end
end
