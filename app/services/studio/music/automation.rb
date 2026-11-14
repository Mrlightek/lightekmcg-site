# frozen_string_literal: true
module Studio
  module Music
    class Automation
      PARAMETERS={"gain"=>[0,1.5],"pan"=>[-1,1],"cutoff"=>[100,18000],"delay"=>[0,0.6]}.freeze
      def self.normalize(raw,tracks:,bars:,version:)
        raise ArgumentError,"Use at most 64 automation lanes" unless raw.is_a?(Array) && raw.length<=64
        raise ArgumentError,"Music automation requires source version 3" if version<3 && raw.any?
        total=0
        lanes=raw.map do |lane|
          raise ArgumentError,"Automation lanes must be objects" unless lane.is_a?(Hash)
          track=tracks.find{|t|t["id"]==lane.fetch("track_id")} || raise(ArgumentError,"Automation references a missing channel")
          parameter=lane.fetch("parameter")
          bounds=PARAMETERS[parameter] || raise(ArgumentError,"Choose volume, pan, filter or delay automation")
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
          {"track_id"=>track["id"],"parameter"=>parameter,"enabled"=>enabled,"points"=>points}
        end
        raise ArgumentError,"Use one automation lane per channel and parameter" unless lanes.map{|l|[l["track_id"],l["parameter"]]}.uniq.length==lanes.length
        lanes
      end
    end
  end
end
