# frozen_string_literal: true
require 'open3'
require 'timeout'
module NevaehOs
  module ProcessRunner
    module_function
    def call(argv, directory:, timeout:120)
      output=+'';errors=+'';status=nil
      environment={'PATH'=>'/usr/bin:/bin','HOME'=>directory.to_s,'TMPDIR'=>directory.to_s,'LC_ALL'=>'C.UTF-8','LANG'=>'C.UTF-8'}
      Open3.popen3(environment,*argv,chdir:directory.to_s,unsetenv_others:true,pgroup:true) do |stdin,stdout,stderr,thread|
        stdin.close
        readers=[[stdout,output],[stderr,errors]].map do |io,buffer|
          Thread.new do
            loop do
              chunk=io.readpartial(4096)
              buffer << chunk if buffer.bytesize < 100000
            end
          rescue EOFError, IOError
            nil
          end
        end
        begin
          Timeout.timeout(timeout) { status=thread.value }
        rescue Timeout::Error
          Process.kill('TERM',-thread.pid) rescue nil
          thread.join(2)
          Process.kill('KILL',-thread.pid) rescue nil
          raise ArgumentError,'Application execution timed out'
        ensure
          readers.each { |reader| reader.join(3) }
          readers.each { |reader| reader.kill if reader.alive? }
        end
      end
      {'stdout'=>output.force_encoding('UTF-8').scrub,'stderr'=>errors.force_encoding('UTF-8').scrub,'exit_code'=>status.exitstatus,'success'=>status.success?}
    rescue Errno::ENOENT
      raise ArgumentError,'The application executable is not installed'
    end
  end
end
