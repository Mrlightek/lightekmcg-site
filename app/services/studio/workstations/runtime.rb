require "json"
require "openssl"
require "base64"
require "fileutils"
require "net/http"
require "digest"
module Studio
  module Workstations
    class Runtime
      IMAGE="lightek/studio-workstation:20261107"
      def self.root = Pathname(ENV.fetch("STUDIO_WORKSTATION_ROOT",Rails.root.join("storage/studio-workstations").to_s))
      def self.directory(session) = root.join("sessions",session.session_key)
      def self.work(session) = directory(session).join("work")
      def self.secret_path = root.join("gateway.key")
      def self.write_state(session)
        path=directory(session);FileUtils.mkdir_p(path,mode:0700)
        data={session_key:session.session_key,owner_id:session.owner_id,site_id:session.site_id,status:session.status,container_id:session.container_id,expires_at:session.expires_at.to_i,origin:session.metadata.fetch("origin")}
        temporary=path.join("session.json.tmp");File.write(temporary,JSON.generate(data),perm:0600);File.rename(temporary,path.join("session.json"))
      end
      def self.ticket(session)
        raise ArgumentError,"Workstation is not ready" unless session.active? && %w[ready saving].include?(session.status)
        secret=File.binread(secret_path)
        raise "Studio workstation gateway key is invalid" unless secret.bytesize>=32
        data=Base64.urlsafe_encode64(JSON.generate({sid:session.session_key,uid:session.owner_id,exp:session.expires_at.to_i}),padding:false)
        signature=Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256",secret,data),padding:false)
        "#{data}.#{signature}"
      end
      def self.command(*args,timeout:30) = Studio::MediaProcess.run!(["docker",*args],timeout:timeout)
      def self.stop(session,status:"stopped")
        command("rm","-f",session.container_id,timeout:15) if session.container_id&.match?(/\A[a-f0-9]{64}\z/)
        session.update!(status:status,port:nil);write_state(session)
      end
      def self.gateway_port
        configuration=root.join("gateway.json")
        Integer(ENV["STUDIO_WORKSTATION_GATEWAY_PORT"] || (configuration.file? ? JSON.parse(File.read(configuration)).fetch("port") : 19080))
      end
      def self.readiness!
        raise "The Studio workstation gateway is not installed. Run the normal deployment/update pipeline." unless secret_path.file?
        response=Net::HTTP.start("127.0.0.1",gateway_port,open_timeout:2,read_timeout:2) { |http| http.get("/health") }
        raise "The Studio workstation gateway is unavailable" unless response.code=="200" && response.body.include?("lightek-workstation")
        command("image","inspect",ENV.fetch("STUDIO_WORKSTATION_IMAGE",IMAGE),timeout:8)
      end
      def self.wait_for_desktop!(session)
        deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+30
        loop do
          begin
            socket=work(session).join(".desktop.sock")
            if File.socket?(socket) && !socket.symlink?
              windows=command("exec","--env","DISPLAY=:99",session.container_id,"xdotool","search","--onlyvisible","--class","Blender",timeout:3)
              return if windows.lines.any? { |line| line.strip.match?(/\A\d+\z/) }
            end
          rescue IOError,SystemCallError,Timeout::Error,RuntimeError
          end
          raise "The native desktop did not start. Check the workstation container log." if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
          sleep 0.2
        end
      end
      def self.open_saved_file(session,name)
        raise ArgumentError,"Invalid saved resource" unless %w[scene.blend project.zip].include?(name)
        path=work(session).join(name)
        file=File.open(path,File::RDONLY|File::NOFOLLOW)
        raise "Saved resource is invalid" unless file.stat.file? && file.stat.size.between?(12,2.gigabytes)
        yield file
      ensure
        file&.close
      end
      def self.digest(file)
        digest=Digest::SHA256.new
        while (chunk=file.read(1024*1024));digest.update(chunk);end
        file.rewind;digest.hexdigest
      end

    end
  end
end
