# frozen_string_literal: true
module Studio
  module Providers
    class LayeredProvider
      def initialize(operation) = @operation=operation
      def call
        actor=User.find(@operation.intent.fetch("user_id"))
        access=Studio::PwaAccess.new("user_id"=>actor.id,"site_id"=>@operation.studio_project.site_id)
        Studio::Workflows::Production.scene!(access,@operation.studio_scene_id)
        LightekPwa::Policy.new(user:actor,site:@operation.studio_project.site).authorize!("studio")
        raise ArgumentError,"Checkout is required before final rendering" unless @operation.metadata["draft_preview"] || @operation.paid?
        graph=Studio::Layered::Composition.normalize(@operation.manifest.fetch("composition_2d"))
        if @operation.metadata["draft_preview"]
          canvas=graph.fetch("canvas")
          raise ArgumentError,"Drafts are limited to two seconds at 640 pixels and 12 fps" unless canvas["duration"]<=2 && [canvas["width"],canvas["height"]].max<=640 && canvas["fps"]<=12
        end
        Studio::Compute::CpuProfile.with_slot do
          Studio::MediaProcess.temporary_directory("lightek-2d-") do |root|
            layers=Studio::Layered::Composition.flatten(graph)
            sources=@operation.layer_sources.blobs.index_by(&:id)
            layers.each_with_index do |layer,index|
              key=layer["template"] ? "template:#{layer['template']}" : "asset:#{layer.fetch('asset_id')}"
              blob=sources.fetch(@operation.metadata.fetch("layer_blobs").fetch(key))
              kind=layer["template"] ? "svg" : "png"
              path="source-#{index}.#{kind}"
              blob.open { |file| FileUtils.cp(file.path,File.join(root,path)) }
              layer["source"]=path;layer["source_kind"]=kind
            end
            spec={"canvas"=>graph.fetch("canvas"),"camera"=>graph.fetch("camera"),"layers"=>layers}
            File.write(File.join(root,"render.json"),JSON.generate(spec))
            FileUtils.cp(Rails.root.join("lib/scripts/studio_layered_renderer.py"),File.join(root,"renderer.py"))
            command=["python3",File.join(root,"renderer.py"),File.join(root,"render.json"),root]
            command=Studio::MediaProcess.container(command.map { |part| part.sub(root,"/work") },root:root,
              image:Studio::NativeBlender::Runtime.image(:media),memory:"512m",pull:false) if Rails.env.production?
            @operation.update!(metadata:@operation.metadata.merge("workflow_phase"=>"compositing"))
            Studio::MediaProcess.run!(command,timeout:180,cancel_if: -> { @operation.reload.status=="cancelled" },on_tick: -> { Studio::Compute::Lease.heartbeat! })
            Studio::Compute::Lease.check!
            path=File.join(root,"scene.mp4")
            raise ArgumentError,"The compositor did not produce a bounded video" unless File.size?(path) && File.size(path)<=64.megabytes
            @operation.with_lock do
              Studio::Compute::Lease.check!
              artifact=@operation.artifacts.find_or_initialize_by(kind:"video",filename:"scene.mp4")
              artifact.file.attach(io:File.open(path),filename:"scene.mp4",content_type:"video/mp4",identify:false)
              artifact.save!
              metrics=JSON.parse(File.read(File.join(root,"metrics.json")))
              @operation.update!(metadata:@operation.metadata.merge("workflow_phase"=>"completed","layered_metrics"=>metrics))
            end
          end
        end
      end
    end
  end
end
