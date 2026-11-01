class StudioBlenderDemoImportJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset=StudioAsset.find(id)
    failure=nil
    asset.with_lock do
      return if asset.status=="ready"
      begin
        Studio::NativeBlender::DemoImport.call(asset)
      rescue StandardError=>error
        failure=error
      end
    end
    raise failure if failure
  end
end
