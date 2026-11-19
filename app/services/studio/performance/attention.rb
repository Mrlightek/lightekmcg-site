# frozen_string_literal: true
require "digest"
module Studio
  module Performance
    class Attention
      def self.inputs(payload)
        return {} if payload["attention"].blank?
        raw=payload["attention"]
        raise ArgumentError,"Choose a scene focal point and bounded attention timing" unless raw.is_a?(Hash) && (raw.keys-%w[kind target_id start end]).empty? && %w[camera object partner].include?(raw["kind"])
        cue={"kind"=>raw["kind"]}
        if raw["kind"]=="object"
          id=raw["target_id"].to_s
          raise ArgumentError,"Choose a focal point from this scene" unless id.match?(/\A[a-zA-Z0-9_-]{1,80}\z/)
          cue["target_id"]=id
        elsif raw.key?("target_id")
          raise ArgumentError,"Camera and partner focal points do not accept an object ID"
        end
        %w[start end].each { |key| value=Float(raw.fetch(key,key=="start" ? 0 : 8));raise ArgumentError,"Use finite attention timing within eight seconds" unless value.finite? && value.between?(0,8);cue[key]=(value*12).round/12.0 }
        raise ArgumentError,"Attention must last at least one frame" unless cue["end"]>cue["start"]
        {"attention"=>cue}
      end
      def self.validate!(character,staging,dialogue:false)
        return unless (cue=character["attention"])
        raise ArgumentError,"A partner focal point needs two-character dialogue" if cue["kind"]=="partner" && !dialogue
        if cue["kind"]=="object"
          raise ArgumentError,"Choose a focal point from the frozen scene setup" unless staging.fetch("objects").any? { |row| row["id"].to_s==cue["target_id"] }
        end
      end
      def self.validate_profile!(character,profile)
        return unless character["attention"]
        binding=profile["attention_binding"];head=profile.dig("bones","head")
        raise ArgumentError,"Register a head and calibrated eye anchor before using focal points" unless binding && head && binding["rig"]==head["object"] && binding["head"]==head["bone"]
      end
      def self.ending(character)
        character.dig("attention","end").to_f
      end
      def self.fingerprint
        Digest::SHA256.hexdigest(%w[attention_v1.py spatial_frame_v1.py].map { |name| Rails.root.join("blender",name).binread }.join)
      end
      def self.apply!(scene:,object:,character:,partner:nil)
        return unless (cue=character["attention"])
        scene.with_lock do
          return if object.reload.definition["attention_plan"]
          validate_profile!(character,object.definition.fetch("character_profile"))
          target=cue["kind"]=="partner" ? partner : cue["kind"]=="object" ? scene.scene_objects.find { |row| row.definition["template_source_object_id"]==cue["target_id"] } : nil
          raise ArgumentError,"The focal point is missing from this prepared scene" if cue["kind"]!="camera" && (!target || target.id==object.id)
          plan=cue.except("target_id").merge("kind"=>cue["kind"]=="camera" ? "camera" : "object","version"=>1,"driver_fingerprint"=>fingerprint)
          plan["target_object_id"]=target.id if target
          object.update!(definition:object.definition.merge("attention_plan"=>plan))
          scene.update!(settings:scene.settings.merge("native_revision"=>scene.settings.fetch("native_revision",0)+1))
        end
      end
    end
  end
end
