require "open3"
require "timeout"
require "tmpdir"
require "fileutils"
require "securerandom"
module Studio
  class MediaProcess
    class Cancelled < StandardError; end
    class BlenderCapacity < StandardError; end
    BLENDER_SLOT = "lightek-blender-slot".freeze
    def self.temp_root
      root=Rails.root.join("storage/studio-tmp").to_s
      FileUtils.mkdir_p(root,mode:0700)
      root
    end
    def self.temporary_directory(prefix,&block)
      Dir.mktmpdir(prefix,temp_root,&block)
    end
    def self.run!(command, blender_workstation: false, **options)
      if command.take(2) == %w[docker run] && (blender_workstation || command.include?("blender") && command.include?("--background"))
        return run_blender!(command, **options)
      end
      run_process!(command, **options)
    end

    def self.run_blender!(command, cleanup_container: true, **options)
      command = command.dup
      memory_index = command.index("--memory") + 1
      budget = run_process!(
        ["python3", Rails.root.join("lib/scripts/studio_worker_limits.py").to_s, "--blender-memory", command[memory_index]],
        timeout: 15, capacity_probe: true
      ).strip
      command[memory_index] = budget
      command[command.index("--name") + 1] = BLENDER_SLOT
      owner = "lightek.blender.attempt=#{SecureRandom.hex(16)}"
      command.insert(2, "--memory-swap", budget, "--label", owner)
      output = run_process!(command, **options, cleanup_container: false, blender_slot: true)
    ensure
      remove_blender_attempt(owner) if owner && (cleanup_container || !output)
    end

    def self.remove_blender_attempt(owner)
      # The slot belongs to the Docker daemon. Clean up by attempt label so
      # contention or cancellation can never remove someone else's render.
      ids, _, status = Open3.capture3("docker", "ps", "-aq", "--no-trunc", "--filter", "label=#{owner}")
      return unless status.success?

      containers = ids.split.grep(/\A[0-9a-f]{64}\z/)
      Open3.capture3("docker", "rm", "-f", *containers) unless containers.empty?
    rescue SystemCallError
      nil
    end

    def self.run_process!(command, timeout:90, cancel_if:nil, stdin_data:nil, cleanup_container:true, on_tick:nil,
        blender_slot:false, capacity_probe:false)
      output="";errors="";status=nil
      Open3.popen3(*command,pgroup:true) do |input,stdout,stderr,wait|
        input.write(stdin_data) if stdin_data
        input.close
        readers = [
          Thread.new do
            while (chunk = stdout.read(16_384))
              output += chunk
              output = output[-1_048_576..] || output
            end
          end,
          Thread.new do
            while (chunk = stderr.read(4096))
              errors += chunk
              errors = errors[-4096..] || errors
            end
          end
        ]
        begin
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          tick=Process.clock_gettime(Process::CLOCK_MONOTONIC)
          until wait.join(0.2)
            if on_tick && Process.clock_gettime(Process::CLOCK_MONOTONIC)-tick>=2
              on_tick.call;tick=Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end
            raise Cancelled, "Operation cancelled by an application administrator" if cancel_if&.call
            raise Timeout::Error, "Media processing exceeded its time limit" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          end
          raise Cancelled, "Operation cancelled by an application administrator" if cancel_if&.call
          status=wait.value
        ensure
          unless status
            Process.kill("TERM",-wait.pid) rescue nil
            unless wait.join(2)
              Process.kill("KILL",-wait.pid) rescue nil
              wait.join
            end
          end
          readers.each(&:join)
        end
      end
      if capacity_probe && !status.success?
        raise BlenderCapacity, errors.strip
      end
      if blender_slot && status.exitstatus == 125 && errors.include?("Conflict.") && errors.include?(BLENDER_SLOT)
        raise Studio::Compute::CpuProfile::Busy, "Waiting for the Blender worker on this server"
      end
      raise "Media processing failed: #{errors[-1000..] || errors}" unless status.success?
      output
    ensure
      if cleanup_container && command&.first=="docker" && (index=command.index("--name"))
        Open3.capture3("docker","rm","-f",command[index+1]) rescue nil
      end
    end
    private_class_method :run_process!, :run_blender!, :remove_blender_attempt
    def self.cpu_limit
      run!(["python3",Rails.root.join("lib/scripts/studio_worker_limits.py").to_s],timeout:15).strip
    end
    def self.container(command, root:, image:, stdin: false, voice_libraries: false, memory: "2g", pull: true)
      name="lightek-media-#{SecureRandom.hex(8)}"
      # Docker drops piped input unless stdin is explicitly attached. No TTY:
      # speech text must reach the engine unchanged through the pipe.
      # Phonemizer clones libespeak before dlopen. Docker's default noexec /tmp
      # cannot map that library; only neural speech gets this bounded mount.
      library_mount=voice_libraries ? ["--tmpfs","/run/lightek-voice:rw,exec,nosuid,nodev,size=16m,mode=1777","--env","TMPDIR=/run/lightek-voice"] : []
      ["docker","run",*(stdin ? ["--interactive"] : []),"--rm","--name",name,"--network","none","--read-only","--cap-drop","ALL","--security-opt","no-new-privileges","--pids-limit","128","--memory",memory,*(pull ? [] : ["--pull","never"]),"--cpus",cpu_limit,"--user","#{Process.uid}:#{Process.gid}","--tmpfs","/tmp:rw,nosuid,size=512m",*library_mount,"-v","#{root}:/work:rw",image]+command
    end
  end
end
