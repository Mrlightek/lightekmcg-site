class StudioAssetIngestJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset = StudioAsset.find(id)
    failure = nil
    asset.with_lock do
      return if asset.status == "ready"
      begin
        Studio::Assets::Ingestor.call(asset)
      rescue StandardError => error
        # Commit the ingestor's failure status before Active Job retries.
        failure = error
      end
    end
    raise failure if failure
  end
end
