module ScreenplayEngine
  class RenderPipeline
    def self.render_headless(manifest_path:, output_video_path:, blender_bin_path: "blender")
      python_script = File.expand_path("headless_render.py")
      manifest_path = File.expand_path(manifest_path)
      output_video_path = File.expand_path(output_video_path)

      # Terminal Command: blender -b -P script.py -- manifest.json output.mp4
      command = "#{blender_bin_path} -b -P #{python_script} -- #{manifest_path} #{output_video_path}"
      
      puts "Triggering Blender Headless Render..."
      system(command)
    end
  end
end

# Usage Example:
# ScreenplayEngine::RenderPipeline.render_headless(
#   manifest_path: "./blender_manifest.json",
#   output_video_path: "./renders/scene_01.mp4"
# )