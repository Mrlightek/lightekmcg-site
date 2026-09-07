# master_pipeline.rb
require_relative 'screenplay_engine'

class MasterPipeline
    
    # 1. Process whole season: Script -> Audio -> Blender 3D -> .MP4 + .SRT
ScreenplayEngine::EpisodicManager.process_series_outline("series_outline.json")

# 2. Automatically publish generated episodes to social platforms
Dir.glob("./dist/episodes/*").each do |episode_folder|
  ScreenplayEngine::SocialPublisher.publish_episode(episode_folder, platform: :all)
end
end