# frozen_string_literal: true
require 'open3'
require 'timeout'
module NevaehOs
  module UbuntuPackages
    HELPER = '/usr/local/sbin/lightek-package-control'
    OPERATIONS = %w[status search show plan install docs refresh].freeze
    module_function
    def authorize!(actor)
      raise ArgumentError, 'Host package administration requires the super administrator' unless actor&.persisted? && actor.role == 'super_admin'
    end
    def call(operation:, package: nil)
      raise ArgumentError, 'Unsupported Ubuntu operation' unless OPERATIONS.include?(operation)
      unless %w[status refresh search].include?(operation)
        raise ArgumentError, 'Use one package name without options or paths' unless package.to_s.match?(/\A[a-z0-9][a-z0-9+.-]{1,100}\z/)
      end
      raise ArgumentError, 'Package control is not installed on this host. Deploy the Nevaeh package-control installer through the native update pipeline.' unless File.file?(HELPER)
      request = {'operation'=>operation};request['package']=package if package
      output = +'';errors = +'';status = nil
      Open3.popen3({'PATH'=>'/usr/bin:/bin'},'sudo','-n',HELPER,pgroup:true) do |stdin,stdout,stderr,thread|
        stdin.write(JSON.generate(request));stdin.close
        readers = [[stdout,output],[stderr,errors]].map do |io,buffer|
          Thread.new do
            loop do
              chunk=io.readpartial(4096)
              buffer << chunk if buffer.bytesize < 400000
            end
          rescue EOFError
            nil
          end
        end
        begin
          Timeout.timeout(1900) { status=thread.value }
        rescue Timeout::Error
          Process.kill('TERM',-thread.pid) rescue nil
          thread.join(2)
          Process.kill('KILL',-thread.pid) rescue nil
          raise ArgumentError, 'Package operation exceeded its execution budget; inspect the host package state before retrying'
        ensure
          readers.each { |reader| reader.join(3) }
          readers.each { |reader| reader.kill if reader.alive? }
        end
      end
      value = JSON.parse(output)
      raise ArgumentError, value['error'] || errors[0,2000] || 'Package operation failed' unless status.success?
      value
    rescue JSON::ParserError
      raise ArgumentError, 'Package helper returned an invalid receipt'
    end
  end
end
