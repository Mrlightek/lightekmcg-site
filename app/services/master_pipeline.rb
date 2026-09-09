class MasterPipeline
  def self.run
    ScreenplayEngine::EpisodicManager.process_series_outline("series_outline.json")

    Dir.glob("./dist/episodes/*").each do |episode_folder|
      ScreenplayEngine::SocialPublisher.publish_episode(
        episode_folder,
        platform: :all
      )
    end
  end
end