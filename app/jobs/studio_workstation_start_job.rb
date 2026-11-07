require "fileutils"
class StudioWorkstationStartJob < ApplicationJob
  queue_as :studio
  def perform(id)
    session=StudioWorkstation.find(id)
    session.with_lock do
      return unless session.status=="starting" && session.active?
      session.update!(status:"building")
    end
    runtime=Studio::Workstations::Runtime;runtime.readiness!
    operation=StudioOperation.find(session.metadata.fetch("operation_id"));operation.update!(status:"running")
    result=Studio::Providers::BlenderProvider.new(operation).call
    path=runtime.work(session);FileUtils.mkdir_p(path,mode:0700)
    FileUtils.cp_r(Dir.glob(result.output_directory.join("*").to_s),path)
    return operation.update!(status:"cancelled") unless session.reload.status=="building" && session.active?
    container=runtime.command("run","-d","--rm","--name","lightek-workstation-#{session.session_key}","--label","lightek.workstation=true","--label","lightek.workstation.session=#{session.session_key}","--network","none","--read-only","--cap-drop","ALL","--security-opt","no-new-privileges","--pids-limit","512","--memory","4g","--cpus",Studio::MediaProcess.cpu_limit,"--shm-size","512m","--user","#{Process.uid}:#{Process.gid}","--tmpfs","/tmp:rw,nosuid,size=1g","--mount","type=bind,source=#{path},target=/work","--mount","type=bind,source=#{Rails.root.join('blender')},target=/engine,readonly",ENV.fetch("STUDIO_WORKSTATION_IMAGE",runtime::IMAGE),timeout:30).strip
    raise "The workstation container identifier is invalid" unless container.match?(/\A[a-f0-9]{64}\z/)
    session.update!(container_id:container);runtime.write_state(session)
    runtime.wait_for_desktop!(session)
    session.reload
    if session.status!="building" || !session.active?
      runtime.stop(session,status:session.expires_at.past? ? "expired" : "stopped");return
    end
    session.update!(status:"ready");runtime.write_state(session);operation.update!(status:"completed")
  rescue StandardError=>error
    if session
      runtime&.command("rm","-f",session.container_id,timeout:10) rescue nil
      session.update!(status:"failed",error_message:error.message.to_s.first(1000),port:nil)
      runtime&.write_state(session)
    end
    operation&.update!(status:"failed",error_message:error.message.to_s.first(1000))
    raise
  end
end
