# frozen_string_literal: true
module Studio
  module Performance
    class Carry
      CALIBRATION={"parcel"=>{"location"=>[-0.83,-0.10,1.08],"scale"=>[0.12,0.05,0.13],"mechanics_carry"=>1},
                   "pickup"=>{"location"=>[-0.83,0.02,0.90],"scale"=>[0.18,0.20,0.05],"mechanics_support"=>"pickup"},
                   "putdown"=>{"location"=>[-0.03,0.02,0.90],"scale"=>[0.18,0.20,0.05],"mechanics_support"=>"putdown"}}.freeze
      def self.objects
        objects=CALIBRATION.map do |id,definition|
          {"id"=>id,"name"=>{"parcel"=>"Carry parcel","pickup"=>"Pickup table","putdown"=>"Put-down table"}.fetch(id),"type"=>"cube",
           "definition"=>definition.deep_dup.merge("material"=>{"color"=>id=="parcel" ? [0.95,0.60,0.08] : [0.14,0.22,0.28]})}
        end
        [-0.83,-0.03].each_with_index { |x,i| objects<<{"id"=>"pedestal_#{i}","name"=>"Table pedestal #{i+1}","type"=>"cube","definition"=>{"location"=>[x,0.10,0.425],"scale"=>[0.05,0.10,0.425],"material"=>{"color"=>[0.08,0.12,0.16]}}} }
        objects
      end
      def self.validate!(cue,staging)
        objects=staging.fetch("objects")
        CALIBRATION.each do |role,expected|
          candidates=role=="parcel" ? objects.select { |row| row["id"].to_s==cue["target_id"] } : objects.select { |row| row.dig("definition","mechanics_support")==role }
          raise ArgumentError,"Choose one calibrated parcel and its two support tables" unless candidates.size==1
          target=candidates.first;definition=target.fetch("definition")
          raise ArgumentError,"Carry v1 needs its calibrated static parcel and table transforms" unless Contact.static_cube?(target) && expected.all? { |key,value| definition[key]==value } && definition.fetch("rotation",[0,0,0])==[0,0,0]
        end
      end
      def self.supports(scene)
        %w[pickup putdown].to_h do |role|
          matches=scene.scene_objects.select { |row| row.definition["mechanics_support"]==role }
          raise ArgumentError,"The frozen #{role} support is missing or ambiguous" unless matches.size==1
          [role,matches.first.id]
        end
      end
    end
  end
end
