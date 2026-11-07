class StudioAssetSaveJob < ApplicationJob
  queue_as :studio
  def perform(id)
    operation=StudioOperation.find(id)
    operation.with_lock do
      return unless operation.status=="pending"
      raise ArgumentError,"Not an asset source export" unless operation.capability=="studio.workspace.blender.asset.save"
      operation.update!(status:"running")
    end
    asset=StudioAsset.find(operation.metadata.fetch("asset_id"))
    result=Studio::Providers::BlenderProvider.new(operation).call
    asset.file.attach(operation.artifacts.find_by!(kind:"blend").file.blob)
    package=operation.artifacts.find_by(kind:"package")
    if package
      asset.bundle.attach(package.file.blob)
      # project.zip always stores its editable entry point at scene.blend.
      asset.update!(metadata:asset.metadata.merge("bundle_relative_source"=>"scene.blend"))
    end
    Studio::Assets::Ingestor.call(asset,source_path:result.output_directory.join("scene.blend").to_s,source_root:result.output_directory.to_s)
    raise "Blender asset preparation failed" unless asset.reload.status=="ready"
    operation.update!(status:"completed")
  rescue StandardError=>error
    asset&.update!(status:"failed",error_message:error.message.to_s.first(1000))
    operation&.update!(status:"failed",error_message:error.message.to_s.first(1000))
    raise
  end
end
