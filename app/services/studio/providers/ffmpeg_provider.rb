require "open3"
require "tmpdir"
require "timeout"
module Studio
  module Providers
    class FfmpegProvider
      def initialize(operation) = @operation=operation
      def call
        raise ArgumentError,"Unsupported edit operation" unless @operation.operation_type=="edit_media"
        actor=User.find(@operation.intent.fetch("user_id"))
        access=Studio::PwaAccess.new("user_id"=>actor.id,"site_id"=>@operation.studio_project.site_id)
        access.projects.find(@operation.studio_project_id)
        raw=@operation.manifest.fetch("timeline")
        ids=Array(raw["clips"]).map{|c|c.fetch("asset_id")}
        assets=StudioAsset.for_actor(access).where(id:ids).index_by(&:id)
        timeline=Studio::Editing::Timeline.normalize(raw,assets:assets)
        Dir.mktmpdir("lightek-edit-") do |root|
          paths=[]
          timeline["clips"].each_with_index do |clip,i|
            file=File.join(root,"source-#{i}#{File.extname(assets.fetch(clip['asset_id']).file.filename.to_s)}")
            File.open(file,"wb"){|out|assets.fetch(clip['asset_id']).file.blob.download{|chunk|out.write(chunk)}}
            paths<<file
          end
          extension=timeline["output"]=="audio" ? "wav" : timeline["export_preset"]=="master" ? "mov" : "mp4"
          output=File.join(root,"master.#{extension}")
          title_paths=timeline.fetch("titles",[]).each_with_index.map do |title,i|
            path=File.join(root,"title-#{i}.txt")
            File.write(path,title.fetch("text"))
            path
          end
          command=Studio::Editing::Timeline.command(timeline,paths:paths,output:output,title_paths:title_paths)
          if Rails.env.production?
            mapped=command.map{|argument|argument.gsub(root,"/work")}
            command=Studio::MediaProcess.container(mapped,root:root,image:Studio::NativeBlender::Runtime.image(:media))
          end
          Studio::MediaProcess.run!(command,timeout:900,cancel_if: -> { @operation.reload.status == "cancelled" })
          raise "Media export did not produce an artifact" unless File.size?(output)
          artifact=@operation.artifacts.create!(kind:timeline["output"]=="audio" ? "audio" : "video",filename:"master.#{extension}")
          artifact.file.attach(io:File.open(output),filename:artifact.filename,content_type:extension=="wav" ? "audio/wav" : extension=="mov" ? "video/quicktime" : "video/mp4")
          {artifact_id:artifact.id}
        end
      end
    end
  end
end
