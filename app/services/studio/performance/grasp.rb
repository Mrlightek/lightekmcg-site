# frozen_string_literal: true
require "json"
module Studio
  module Performance
    class Grasp
      CALIBRATION={"ball"=>{"location"=>[-0.83,-0.24,1.0],"scale"=>[0.045,0.045,0.045],"mechanics_grasp"=>1},
                   "grasp"=>{"location"=>[-0.83,-0.24,0.905],"scale"=>[0.18,0.20,0.05],"mechanics_support"=>"grasp"}}.freeze
      def self.physical_profile
        JSON.parse(File.binread(File.expand_path("../../../../blender/physics/human_v1.json",__dir__)))
      end
      def self.objects
        CALIBRATION.map do |id,definition|
          {"id"=>id,"name"=>id=="ball" ? "Contact sphere" : "Grasp table","type"=>id=="ball" ? "sphere" : "cube",
           "definition"=>definition.deep_dup.merge("material"=>{"color"=>id=="ball" ? [0.95,0.60,0.08] : [0.14,0.22,0.28]})}
        end+[
          {"id"=>"grasp_pedestal","name"=>"Grasp pedestal","type"=>"cube","definition"=>{"location"=>[-0.83,-0.24,0.4275],"scale"=>[0.05,0.10,0.4275],"material"=>{"color"=>[0.08,0.12,0.16]}}},
          {"id"=>"grasp_wide","name"=>"Grasp wide","type"=>"camera","definition"=>{"location"=>[-0.45,-5,1.2],"look_at"=>[-0.45,-0.4,1.2],"camera_type"=>"ORTHO","ortho_scale"=>3.8}},
          {"id"=>"grasp_close","name"=>"Finger contact close-up","type"=>"camera","definition"=>{"location"=>[-1.15,0.5,1.65],"look_at"=>[-0.83,-0.24,1.07],"camera_type"=>"ORTHO","ortho_scale"=>0.65}}
        ]
      end
      def self.validate!(cue,staging)
        raise ArgumentError,"Choose the calibrated contact sphere" unless cue["target_id"]==staging.fetch("objects").find { |row| row.dig("definition","mechanics_grasp")==1 }&.fetch("id")&.to_s
        CALIBRATION.each do |role,expected|
          matches=staging.fetch("objects").select { |row| role=="ball" ? row["id"].to_s==cue["target_id"] : row.dig("definition","mechanics_support")==role }
          raise ArgumentError,"Choose the sphere and its calibrated static table" unless matches.size==1
          row=matches.first;definition=row.fetch("definition")
          raise ArgumentError,"The contact study needs its original static calibration" unless row["type"]==(role=="ball" ? "sphere" : "cube") && expected.all? { |key,value| definition[key]==value } && definition.fetch("rotation",[0,0,0])==[0,0,0] && %w[animation story_relation authoring_commands].none? { |key| definition[key].present? }
        end
      end
      def self.supports(scene)
        rows=scene.scene_objects.select { |row| row.definition["mechanics_support"]=="grasp" }
        raise ArgumentError,"The frozen grasp table is missing or ambiguous" unless rows.size==1
        {"grasp"=>rows.first.id}
      end
    end
  end
end
