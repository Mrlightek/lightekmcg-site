# frozen_string_literal: true
require "digest"
module Studio
  module Performance
    class MotionPlan
      def self.normalize(raw, profile)
        raise ArgumentError,"Use at most 32 motion clips per character" unless raw.is_a?(Array) && raw.length<=32
        ids=[]
        clips=raw.map do |clip|
          id=clip.fetch("id").to_s
          raise ArgumentError,"Motion clip IDs must be unique" unless id.match?(/\A[a-zA-Z0-9_-]{8,100}\z/) && !ids.include?(id)
          ids<<id
          action=Array(profile["motions"]).find{|item|item["id"]==clip["action_id"]} || raise(ArgumentError,"Choose a motion from this character's registered source")
          first=Take.number(clip.fetch("source_in"),action.fetch("frame_start"),action.fetch("frame_end"))
          last=Take.number(clip.fetch("source_out"),action.fetch("frame_start"),action.fetch("frame_end"))
          raise ArgumentError,"The source out frame must follow the in frame" unless last>first
          speed=Take.number(clip.fetch("speed",1),0.25,4)
          repeat=Take.number(clip.fetch("repeat",1),1,20);layer=Take.number(clip.fetch("layer",0),0,3)
          raise ArgumentError,"Use 1–20 repeats and layers 0–3" unless repeat==repeat.to_i && layer==layer.to_i
          repeat=repeat.to_i;layer=layer.to_i
          duration=(last-first)/Float(action.fetch("fps"))/speed*repeat
          start=Take.number(clip.fetch("start",0),0,600)
          raise ArgumentError,"Motion clips must last 0.05–60 seconds and end within ten minutes" unless duration.finite? && duration.between?(0.05,60) && start+duration<=600
          blend_in=Take.number(clip.fetch("blend_in",0),0,[3,duration/2].min)
          blend_out=Take.number(clip.fetch("blend_out",0),0,[3,duration/2].min)
          mode=clip.fetch("mode","REPLACE")
          raise ArgumentError,"Choose replace or additive blending" unless %w[REPLACE ADD].include?(mode)
          {"id"=>id,"action_id"=>action["id"],"source_in"=>first,"source_out"=>last,"start"=>start,"duration"=>duration,
            "speed"=>speed,"repeat"=>repeat,"strength"=>Take.number(clip.fetch("strength",1),0,1),"layer"=>layer,"blend_in"=>blend_in,"blend_out"=>blend_out,"mode"=>mode}
        end
        actions=Array(profile["motions"]).index_by{|action|action["id"]}
        clips.group_by{|clip|[actions.fetch(clip["action_id"])["rig"],clip["layer"]]}.each_value do |layer|
          ordered=layer.sort_by{|clip|clip["start"]}
          ordered.each_cons(2) do |a,b|
            overlap=a["start"]+a["duration"]-b["start"]
            raise ArgumentError,"Overlapping clips on one layer need matching blend-out and blend-in time" if overlap>0.00001 && overlap>[a["blend_out"],b["blend_in"]].min+0.00001
          end
          raise ArgumentError,"Use another layer instead of overlapping three clips" if ordered.each_cons(3).any?{|a,_,c|a["start"]+a["duration"]>c["start"]}
        end
        clips
      end
      def self.save(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id.to_i==access.site_id.to_i
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"A motion request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        fingerprint=Digest::SHA256.hexdigest(payload.slice("object_id","clips","motion_revision").to_json)
        result=nil
        scene.with_lock do
          receipts=scene.settings.fetch("motion_receipts",{})
          if receipts[key]
            raise ArgumentError,"This request key belongs to a different motion arrangement" unless receipts[key]["fingerprint"]==fingerprint
            return receipts[key]
          end
          object=scene.scene_objects.find(payload.fetch("object_id"))
          profile=object.definition["character_profile"] || raise(ArgumentError,"Choose a Cast member first")
          revision=object.definition.fetch("motion_revision",0)
          raise ArgumentError,"These motions changed. Reload the saved arrangement before editing." unless revision==Integer(payload.fetch("motion_revision",0))
          clips=normalize(payload.fetch("clips"),profile)
          scene.lock_version=Integer(payload.fetch("lock_version"))
          object.update!(definition:object.definition.merge("motion_clips"=>clips,"motion_revision"=>revision+1))
          fps=scene.settings.fetch("fps",24).to_f/scene.settings.fetch("fps_base",1)
          ending=(clips.map{|clip|(clip["start"]+clip["duration"])*fps}.max || 1).ceil
          result={"scene_id"=>scene.id,"object_id"=>object.id,"motion_revision"=>revision+1,"lock_version"=>scene.lock_version+1,"fingerprint"=>fingerprint}
          scene.update!(settings:scene.settings.merge("frame_end"=>[scene.settings.fetch("frame_end",1),ending].max,
            "native_revision"=>scene.settings.fetch("native_revision",0)+1,"motion_receipts"=>receipts.to_a.last(99).to_h.merge(key=>result)))
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before saving motion clips."
      end
    end
  end
end
