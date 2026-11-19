# frozen_string_literal: true
require "digest"
module Studio
  module Performance
    # Scene ViewModel: immutable, versioned action plans consume source rig contracts.
    class Mechanics
      PROFILE="illustrated_biped".freeze
      VERSION=1
      def self.bindings
        {"profile"=>PROFILE,"version"=>VERSION,"rig"=>"PerformerRig","body"=>"Body","support"=>"Pelvis support",
         "arms"=>%w[L R].to_h { |side| [side,{"upper"=>"Arm.#{side}","lower"=>"Forearm.#{side}","hand"=>"Hand #{side}"}] },
         "legs"=>%w[L R].to_h { |side| [side,{"upper"=>"Leg.#{side}","lower"=>"Shin.#{side}","foot"=>"Boot #{side}"}] }}
      end
      def self.register(objects,raw)
        return nil if raw.blank?
        raise ArgumentError,"Unsupported mechanics calibration" unless raw==bindings
        rig=objects.find { |row| row["name"]==raw["rig"] && row.dig("definition","native_type")=="ARMATURE" }
        bones=Array(rig&.dig("definition","bones"))
        names=bones.map { |bone| bone["name"] }
        raise ArgumentError,"Missing calibrated mechanics bones" unless (%w[Body Leg.L Leg.R Shin.L Shin.R Arm.L Arm.R Forearm.L Forearm.R]-names).empty?
        [*raw["legs"].values,*raw["arms"].values].each do |leg|
          raise ArgumentError,"Bind connected mechanics legs" unless bones.find { |bone| bone["name"]==leg["lower"] }["parent"]==leg["upper"]
        end
        raise ArgumentError,"Missing calibrated support geometry" unless ([raw["support"],*raw["legs"].values.map { |leg| leg["foot"] },*raw["arms"].values.map { |arm| arm["hand"] }]-objects.select { |row| row.dig("definition","native_type")=="MESH" }.map { |row| row["name"] }).empty?
        raw.deep_dup
      end
      def self.inputs(payload)
        return {} if payload["mechanics"].blank?
        raw=payload["mechanics"]
        raise ArgumentError,"Choose the versioned bench performance" unless raw.is_a?(Hash) && raw.keys.sort==%w[action target_id version] && raw["action"]=="bench" && raw["version"]==VERSION && raw["target_id"].to_s.match?(/\A[a-zA-Z0-9_-]{1,80}\z/)
        {"mechanics"=>raw.merge("target_id"=>raw["target_id"].to_s)}
      end
      def self.validate!(character,staging)
        return unless (cue=character["mechanics"])
        raise ArgumentError,"Bench performance coordinates its own movement and contacts" if character["contact"] || character["entrance"]!="none" || character["body_action"]!="still" || character["gesture"]!="still"
        raise ArgumentError,"Clear saved source motion before using coordinated mechanics" if staging.dig("actor_motion","motion_clips").present?
        target=staging.fetch("objects").find { |object| object["id"].to_s==cue["target_id"] }
        raise ArgumentError,"Choose the calibrated bench seat" unless target && Contact.static_cube?(target) && target.dig("definition","mechanics_seat")==VERSION
        definition=target.fetch("definition");location=definition["location"];scale=definition["scale"]
        raise ArgumentError,"The version 1 bench needs its calibrated height and dimensions" unless location==[0,0.27,0.40] && scale==[0.8,0.19,0.04] && definition.fetch("rotation",[0,0,0])==[0,0,0]
      end
      def self.validate_profile!(character,profile)
        return unless character["mechanics"]
        raise ArgumentError,"Build a new illustrated performer with version 1 mechanics bindings" unless profile["mechanics"]==bindings
      end
      def self.driver_fingerprint
        Digest::SHA256.hexdigest(%w[bench_v1.py kinematics_v1.py].map { |name| Rails.root.join("blender",name).binread }.join)
      end
      def self.apply!(scene:,object:,character:)
        return unless (cue=character["mechanics"])
        scene.with_lock do
          return if object.reload.definition["mechanics_plan"]
          validate_profile!(character,object.definition.fetch("character_profile"))
          target=scene.scene_objects.find { |row| row.definition["template_source_object_id"]==cue["target_id"] }
          raise ArgumentError,"The frozen bench seat is missing" unless target
          plan={"driver"=>"bench","version"=>VERSION,"profile"=>PROFILE,"target_object_id"=>target.id,"driver_fingerprint"=>driver_fingerprint,"source_blob_id"=>object.definition.dig("character_profile","source_blob_id"),
                "phases"=>{"walk"=>[0,2],"turn"=>[2,2.5],"sit"=>[2.5,3.25],"seated"=>[3.25,6.4],"stand"=>[6.4,7.25],"rest"=>[7.25,8]}}
          object.update!(definition:object.definition.merge("location"=>[0,-0.24,0],"rotation"=>[0,0,0],"scale"=>[1,1,1],"mechanics_plan"=>plan))
          scene.update!(settings:scene.settings.merge("native_revision"=>scene.settings.fetch("native_revision",0)+1))
        end
      end
    end
  end
end
