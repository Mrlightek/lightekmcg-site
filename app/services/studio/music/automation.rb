# frozen_string_literal: true
module Studio
  module Music
    class Automation
      PARAMETERS={"gain"=>[0,1.5],"pan"=>[-1,1],"cutoff"=>[100,18000],"delay"=>[0,0.6]}.freeze
      def self.normalize(raw,tracks:,bars:,version:,mixer: nil)
        raise ArgumentError,"Use at most 64 automation lanes" unless raw.is_a?(Array) && raw.length<=64
        raise ArgumentError,"Music automation requires source version 3" if version<3 && raw.any?
        total=0
        lanes=raw.map do |lane|
          raise ArgumentError,"Automation lanes must be objects" unless lane.is_a?(Hash)
          target_keys=lane.keys & %w[track_id bus_id master]
          raise ArgumentError,"Choose exactly one automation target" unless target_keys.length==1
          target_key=target_keys.first;effect=nil
          if target_key=="track_id"
            track=tracks.find{|t|t["id"]==lane["track_id"]} || raise(ArgumentError,"Automation references a missing channel")
            owner=track
            target={"track_id"=>track["id"]}
          else
            raise ArgumentError,"Bus and master automation require music source version 7" if version<7
            if target_key=="bus_id"
              bus=mixer&.fetch("buses",[])&.find{|b|b["id"]==lane["bus_id"]} || raise(ArgumentError,"Automation references a missing bus")
              owner=bus
              target={"bus_id"=>bus["id"]}
            else
              raise ArgumentError,"Master automation target must be true" unless lane["master"]==true
              owner=mixer&.fetch("master",{}) || {}
              target={"master"=>true}
            end
          end
          parameter=lane.fetch("parameter")
          allowed=target_key=="master" ? %w[gain] : target_key=="bus_id" ? %w[gain pan] : PARAMETERS.keys
          if lane.key?("effect_id")
            raise ArgumentError,"Insert automation requires music source version 8" if version<8
            effect=Array(owner["effects"]).find{|e|e["id"]==lane["effect_id"]} || raise(ArgumentError,"Automation references a missing insert")
            target["effect_id"]=effect["id"]
            allowed=Mixer::EFFECTS.fetch(effect["kind"]).keys-["distortion"]
          end
          raise ArgumentError,"Unsupported parameter for this automation target" unless allowed.include?(parameter)
          bounds=effect ? Mixer::EFFECTS.fetch(effect["kind"]).fetch(parameter).first(2) : PARAMETERS.fetch(parameter)
          points=lane.fetch("points")
          raise ArgumentError,"Use at most 128 points per automation lane" unless points.is_a?(Array) && points.length<=128
          total+=points.length
          raise ArgumentError,"Use at most 2048 automation points per song" if total>2048
          points=points.map do |point|
            raise ArgumentError,"Automation points must be objects" unless point.is_a?(Hash)
            curve=point.fetch("curve","linear")
            raise ArgumentError,"Automation arrival curves are linear or hold" unless %w[linear hold].include?(curve)
            {"beat"=>Composition.number(point.fetch("beat"),0,bars*4),"value"=>Composition.number(point.fetch("value"),*bounds),"curve"=>curve}
          end.sort_by{|point|point["beat"]}
          raise ArgumentError,"Automation point beats must be unique" unless points.map{|point|point["beat"].round(6)}.uniq.length==points.length
          enabled=lane.fetch("enabled",true)
          raise ArgumentError,"Automation enabled must be true or false" unless [true,false].include?(enabled)
          target.merge("parameter"=>parameter,"enabled"=>enabled,"points"=>points)
        end
        raise ArgumentError,"Use one automation lane per target and parameter" unless lanes.map{|l|[l.slice("track_id","bus_id","master","effect_id"),l["parameter"]]}.uniq.length==lanes.length
        lanes
      end
    end
  end
end
