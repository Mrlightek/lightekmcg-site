require 'json'
require 'fileutils'

# Sample Series Outline Format (series_outline.json)

# Pass this file format directly into the EpisodicManager to generate an entire season automatically:
# {
#   "series_title": "Ashgray Underground",
#   "episodes": [
#     {
#       "title": "The Ignited Spark",
#       "scene_name": "Sector 4 Ruins",
#       "environment": "collapsed_sector",
#       "script": [
#         { "speaker": "Kess", "emotion": "frantic", "text": "The conduit is bleeding power! Hand me the solder!" },
#         { "speaker": "Ren", "emotion": "desperate", "text": "Kess, step back! The whole ceiling is coming down!" }
#       ]
#     },
#     {
#       "title": "Echoes in the Deep",
#       "scene_name": "Sub-Strata Workshop",
#       "environment": "subterranean_workshop",
#       "script": [
#         { "speaker": "Kess", "emotion": "hopeful", "text": "Wait... that's not static. That's a frequency pattern." },
#         { "speaker": "Ren", "emotion": "grief", "text": "We haven't heard a signal from below since the crash..." }
#       ]
#     }
#   ]
# }

module ScreenplayEngine
  class EpisodicManager
    OUTPUT_BASE = "./dist/episodes"

    def self.process_series_outline(outline_filepath)
      unless File.exist?(outline_filepath)
        puts "Error: Outline file #{outline_filepath} not found."
        return
      end

      outline = JSON.parse(File.read(outline_filepath), symbolize_names: true)
      series_title = outline[:series_title].downcase.gsub(/\s+/, '_')

      puts "Starting production batch for Series: '#{outline[:series_title]}'"
      puts "Total Episodes queued: #{outline[:episodes].size}"
      puts "----------------------------------------------------"

      outline[:episodes].each_with_index do |ep_data, idx|
        ep_number = sprintf("%02d", idx + 1)
        ep_folder = File.join(OUTPUT_BASE, "#{series_title}_ep#{ep_number}")
        FileUtils.mkdir_p(ep_folder)

        puts "Processing Episode #{ep_number}: '#{ep_data[:title]}'"

        # 1. Generate Episode Manifest Payload
        manifest = build_episode_manifest(ep_data, ep_number)
        manifest_path = File.join(ep_folder, "manifest.json")
        File.write(manifest_path, JSON.pretty_generate(manifest))

        # 2. Build .srt Caption File
        srt_path = File.join(ep_folder, "captions.srt")
        SubtitleGenerator.export_srt(manifest[:script_data], srt_path, 30)

        # 3. Trigger Headless Blender Render
        video_out_path = File.join(ep_folder, "final_episode.mp4")
        RenderPipeline.render_headless(
          manifest_path: manifest_path,
          output_video_path: video_out_path
        )

        puts " Episode #{ep_number} compiled successfully: #{video_out_path}\n\n"
      end

      puts "Series processing complete! All assets saved to #{OUTPUT_BASE}"
    end

    private

    def self.build_episode_manifest(ep_data, ep_number)
      script_lines = ep_data[:script].map.with_index do |line, idx|
        start_frame = (idx + 1) * 48 # 2-second timing interval

        {
          speaker: line[:speaker],
          emotion: line[:emotion].to_sym,
          text: line[:text],
          start_frame: start_frame,
          signature_shot: AdvancedCinematography.select_signature_shot(line[:emotion].to_sym),
          lighting_state: LightingDirector.generate_lighting_states(line[:speaker], line[:emotion].to_sym),
          facial_expression: FacialExpressionDirector.generate_expression_keys(line[:emotion].to_sym, start_frame)
        }
      end

      {
        metadata: { episode: ep_number, title: ep_data[:title] },
        scene_info: { name: ep_data[:scene_name], environment: ep_data[:environment].to_sym },
        social_media: SocialMediaExporter.configure_target(:tiktok_reels),
        sci_fi_vfx: SciFiVFXDirector.select_effects(:frantic),
        script_data: script_lines
      }
    end
  end
end