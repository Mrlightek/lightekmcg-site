require "timeout"

module Studio
  module MacroMaker
    class EffectCraftRenderer
      class RenderFailure < StandardError; end

      def self.render!(executable:, project:, output:, timeout:)
        tail = +""
        last_percent = nil
        finished = false
        IO.pipe do |reader, writer|
          raise Timeout::Error unless timeout.positive?

          pid = Process.spawn([executable, executable], "render", project, "--out", output,
            "--format", "h264", "--progress", in: File::NULL, out: File::NULL, err: writer, pgroup: true)
          process = Process.detach(pid)
          writer.close
          Timeout.timeout(timeout) do
            reader.each_line do |line|
              line = line.scrub
              tail << line
              tail = tail[-1000..] if tail.length > 1000
              match = /\Aprogress (\d+) (\d+) /.match(line)
              next unless match && match[2].to_i.positive? && block_given?

              percent = [100 * match[1].to_i / match[2].to_i, 100].min
              next if percent == last_percent

              last_percent = percent
              yield percent
            end
            status = process.value
            finished = true
            raise RenderFailure, "EffectCraft render exited with #{status.exitstatus || "signal #{status.termsig}"}" unless status.success?
            raise RenderFailure, "EffectCraft produced no video" unless File.file?(output) && File.size?(output)
          end
        ensure
          if pid && !finished
            begin
              Process.kill("KILL", -pid)
            rescue Errno::ESRCH
            end
            process&.join
          end
        end
      rescue Timeout::Error
        raise step_error(:timeout, tail, "motion job time limit exceeded")
      rescue RenderFailure => error
        raise step_error(:protocol_error, tail, error.message)
      rescue SystemCallError, IOError => error
        raise step_error(:died, tail, error.message)
      end

      def self.step_error(reason, stderr, detail)
        RecipeSession::StepError.new(step_index: nil, command: "render", engine: "effectcraft",
          reason: reason, stderr: stderr, detail: detail)
      end
      private_class_method :step_error
    end
  end
end
