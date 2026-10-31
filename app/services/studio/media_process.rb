require "open3"
require "timeout"
module Studio
  class MediaProcess
    class Cancelled < StandardError; end
    def self.run!(command, timeout:90, cancel_if:nil)
      output="";errors="";status=nil
      Open3.popen3(*command,pgroup:true) do |input,stdout,stderr,wait|
        input.close
        readers=[Thread.new{while(chunk=stdout.read(16_384));output=(output+chunk).last(1_048_576);end},Thread.new{while(chunk=stderr.read(4096));errors=(errors+chunk).last(4096);end}]
        begin
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          until wait.join(0.2)
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
      raise "Media processing failed: #{errors.last(1000)}" unless status.success?
      output
    ensure
      if command&.first=="docker" && (index=command.index("--name"))
        Open3.capture3("docker","rm","-f",command[index+1]) rescue nil
      end
    end
    def self.container(command, root:, image:)
      name="lightek-media-#{SecureRandom.hex(8)}"
      ["docker","run","--rm","--name",name,"--network","none","--read-only","--cap-drop","ALL","--security-opt","no-new-privileges","--pids-limit","128","--memory","2g","--cpus","2","--user","#{Process.uid}:#{Process.gid}","--tmpfs","/tmp:rw,nosuid,size=512m","-v","#{root}:/work:rw",image]+command
    end
  end
end
