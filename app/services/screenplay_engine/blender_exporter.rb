require 'json'

module ScreenplayEngine
  class BlenderExporter
    def self.export_scene(scene_data, file_path = "blender_manifest.json")
      blender_payload = {
        metadata: {
          generated_at: Time.now.iso8601,
          engine_version: "1.0"
        },
        scene_info: {
          name: scene_data[:scene_name],
          environment_type: scene_data[:environment]
        },
        environment_setup: {
          lighting_style: scene_data[:lighting],
          score_cue: scene_data[:score]
        },
        script_data: scene_data[:lines], # Array of { speaker:, emotion:, text: }
        blender_nodes: parse_set_objects(scene_data[:setting])
      }

      File.write(file_path, JSON.pretty_generate(blender_payload))
      puts "Successfully exported manifest to #{file_path}"
    end

    private

    # Scrapes setting strings to flag basic mesh primitives Blender should spawn
    def self.parse_set_objects(setting_text)
      nodes = []
      nodes << { type: "LIGHT", name: "Key_Light", light_type: "POINT", energy: 1000 }
      nodes << { type: "CAMERA", name: "Main_Camera", location: [0, -5, 1.5], rotation: [1.57, 0, 0] }

      # Quick primitive generator based on text keywords
      if setting_text.include?("workbench") || setting_text.include?("furniture")
        nodes << { type: "MESH", primitive: "CUBE", name: "Workbench_Placeholder", location: [0, 2, 0] }
      end
      if setting_text.include?("conduits") || setting_text.include?("beams")
        nodes << { type: "MESH", primitive: "CYLINDER", name: "Conduit_Pipe", location: [-2, 3, 1] }
      end

      nodes
    end
  end
end