# frozen_string_literal: true
module Studio
  module Performance
    class Acting
      EMOTIONS=%w[neutral friendly curious surprised].freeze
      ACTIONS={"still"=>nil,"point_left"=>"Point left","point_right"=>"Point right"}.freeze
      ENTRANCES=%w[none from_left from_right].freeze
      def self.inputs(payload)
        emotion=payload.fetch("emotion","neutral").to_s
        action=payload.fetch("body_action","still").to_s
        entrance=payload.fetch("entrance","none").to_s
        raise ArgumentError,"Choose a supported facial cue" unless EMOTIONS.include?(emotion)
        raise ArgumentError,"Choose a supported body action" unless ACTIONS.key?(action)
        raise ArgumentError,"Choose a supported entrance" unless ENTRANCES.include?(entrance)
        {"emotion"=>emotion,"body_action"=>action,"entrance"=>entrance}
      end
      def self.expressions(character,profile,duration)
        emotion=character.fetch("emotion","neutral")
        values={"neutral"=>{},"friendly"=>{"smile"=>0.45},"curious"=>{"brow_raise"=>0.45},"surprised"=>{"brow_raise"=>0.85}}.fetch(emotion)
        values.map do |control,value|
          raise ArgumentError,"This Cast performer needs a bound #{control} control for the selected facial cue" unless profile.fetch("bindings").key?(control)
          {"control"=>control,"start"=>0,"end"=>duration,"value"=>value}
        end
      end
      def self.motion(profile,name)
        Array(profile["motions"]).find { |item| item["name"]==name } || raise(ArgumentError,"This saved performer has no #{name} action. Build a new illustrated performer or register that action in Cast.")
      end
      def self.gesture!(character)
        if {"point_left"=>"wave_left","point_right"=>"wave_right"}[character["body_action"]]==character["gesture"] && character["gesture"]
          raise ArgumentError,"Use a head gesture or no added gesture with a pointing action on that arm"
        end
      end
      def self.validate!(character,profile)
        gesture!(character)
        expressions(character,profile,1)
        motion(profile,ACTIONS.fetch(character.fetch("body_action","still"))) if character.fetch("body_action","still")!="still"
        motion(profile,"Step in place") if character.fetch("entrance","none")!="none"
      end
      def self.clip(profile,name,id,start,duration)
        action=motion(profile,name);seconds=(action.fetch("frame_end")-action.fetch("frame_start"))/Float(action.fetch("fps"))
        {"id"=>id,"action_id"=>action.fetch("id"),"source_in"=>action.fetch("frame_start"),"source_out"=>action.fetch("frame_end"),"start"=>start,"speed"=>seconds/duration,"repeat"=>1,"mode"=>"REPLACE"}
      end
      def self.apply!(access:,scene:,object:,character:,turns:,key:)
        return if character.fetch("emotion","neutral")=="neutral" && character.fetch("body_action","still")=="still" && character.fetch("entrance","none")=="none"
        scene.with_lock do
          return if object.reload.definition["guided_acting_applied"]
          profile=object.definition.fetch("character_profile");validate!(character,profile)
          entrance=character.fetch("entrance","none");action=character.fetch("body_action","still");clips=[]
          if entrance!="none"
            clips<<clip(profile,"Step in place",key+"-step",0,0.85)
          end
          if action!="still"
            turns.each_with_index { |turn,index| clips<<clip(profile,ACTIONS.fetch(action),key+"-point-#{index}",turn["start"],[turn["duration"],0.25].max) }
          end
          if clips.any?
            MotionPlan.save(access:access,payload:{"scene_id"=>scene.id,"object_id"=>object.id,"clips"=>clips,"lock_version"=>scene.reload.lock_version,"motion_revision"=>object.definition.fetch("motion_revision",0),"request_key"=>key+"-motion"})
          end
          scene.reload
          definition=object.reload.definition.deep_dup
          if entrance!="none"
            location=definition.fetch("location",[0,0,0]);first=location.dup;first[0]+=entrance=="from_left" ? -0.8 : 0.8
            definition["animation"]={"fps"=>12,"frames"=>[{"frame"=>1,"location"=>first},{"frame"=>12,"location"=>location}]}
          end
          object.update!(definition:definition.merge("guided_acting_applied"=>true,"acting_direction"=>character.slice("emotion","body_action","entrance")))
          scene.update!(settings:scene.settings.merge("native_revision"=>scene.settings.fetch("native_revision",0)+1))
        end
      end
    end
  end
end
