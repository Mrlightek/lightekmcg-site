require "digest"
class StudioWorkstationSaveJob < ApplicationJob
  queue_as :studio
  def perform(id)
    session=StudioWorkstation.find(id);runtime=Studio::Workstations::Runtime
    nonce=nil;receipt={}
    session.with_lock do
      return unless session.status=="saving" && session.active?
      nonce=session.metadata.fetch("save_nonce")
      temporary=runtime.work(session).join(".request-#{SecureRandom.hex(8)}")
      File.open(temporary,File::WRONLY|File::CREAT|File::EXCL|File::NOFOLLOW,0600) { |file| file.write(JSON.generate({nonce:nonce})) }
      File.rename(temporary,runtime.work(session).join(".studio-save-request.json"))
    end
    runtime.command("exec","--env","DISPLAY=:99",session.container_id,"xdotool","key","--clearmodifiers","F8",timeout:8)
    deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+30
    receipt_path=runtime.work(session).join(".studio-save-receipt.json")
    loop do
      if receipt_path.file? && !receipt_path.symlink?
        receipt=File.open(receipt_path,File::RDONLY|File::NOFOLLOW) { |file| JSON.parse(file.read(8192)) } rescue {}
        break if receipt["nonce"]==nonce
      end
      raise "Blender did not confirm the save. Close open modal dialogs and retry." if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
      sleep 0.2
    end
    runtime.open_saved_file(session,"scene.blend") { |file| raise "Blender source changed during save" unless runtime.digest(file)==receipt.fetch("sha256") }
    access=Studio::PwaAccess.new("user_id"=>session.owner_id,"site_id"=>session.site_id)
    asset=StudioAsset.find_or_initialize_by(owner_id:session.owner_id,request_key:"workstation-#{session.session_key}-#{nonce}")
    unless asset.persisted?
      asset.assign_attributes(site_id:session.site_id,studio_project:session.studio_scene.studio_project,name:"#{session.studio_scene.name} · native edit".first(160),kind:"blend",status:"processing",metadata:{"sources"=>session.metadata.fetch("credits",[]),"workstation_session"=>session.session_key,"bundle_relative_source"=>"scene.blend"})
      runtime.open_saved_file(session,"project.zip") do |file|
        raise "Saved package changed during save" unless runtime.digest(file)==receipt.fetch("bundle_sha256")
        blob=ActiveStorage::Blob.create_and_upload!(io:file,filename:"project.zip",content_type:"application/zip",identify:false)
        asset.bundle.attach(blob)
      end
      asset.save!
    end
    unless asset.status=="ready"
      Dir.mktmpdir("studio-workstation-import-") do |folder|
        asset.bundle.blob.open do |zip|
          Studio::MediaProcess.run!(["python3",Rails.root.join("blender/extract_demo.py").to_s,zip.path,folder],timeout:90)
          source=Pathname(folder).join("scene.blend")
          raise "The native package has no scene.blend entry" unless source.file? && !source.symlink?
          asset.file.attach(io:File.open(source,"rb"),filename:"scene.blend",content_type:"application/x-blender",identify:false)
          Studio::Assets::Ingestor.call(asset,source_path:source.to_s,source_root:folder)
        end
      end
    end
    result=Studio::NativeBlender::NativeTemplate.call(access:access,payload:{"asset_id"=>asset.id,"request_key"=>"workstation-project-#{session.session_key}-#{nonce}"})
    session.reload
    next_status=session.status=="saving" ? (session.expires_at.future? ? "ready" : "expired") : session.status
    session.update!(status:next_status,error_message:nil,metadata:session.metadata.merge("saved_asset_id"=>asset.id,"saved_scene_id"=>result.fetch(:scene_id),"saved_at"=>Time.current.iso8601))
    runtime.write_state(session)
  rescue StandardError=>error
    session&.reload
    status=session && %w[stopped expired failed].include?(session.status) ? session.status : session&.expires_at&.future? ? "ready" : "expired"
    session&.update!(status:status,error_message:error.message.to_s.first(1000))
    runtime&.write_state(session) if session
    raise
  end
end
