# frozen_string_literal: true
module Studio
  module Music
    class Scoring
      def self.normalize(raw,version:,duration:)
        raise ArgumentError,"Picture scoring requires music source version 6" if version<6
        raise ArgumentError,"Scoring settings must be an object" unless raw.is_a?(Hash)
        start=Composition.number(raw.fetch("start",0),0,600)
        raise ArgumentError,"The score must fit within the ten-minute edit" if start+duration>600.000001
        cues=raw.fetch("cues",[])
        raise ArgumentError,"Use at most 64 picture cues" unless cues.is_a?(Array) && cues.length<=64
        cues=cues.map do |cue|
          raise ArgumentError,"Picture cues must be objects" unless cue.is_a?(Hash)
          {"id"=>Patterns.id(cue.fetch("id")),"name"=>cue.fetch("name","Cue").to_s.first(60),"time"=>Composition.number(cue.fetch("time"),0,600)}
        end.sort_by{|cue|cue["time"]}
        raise ArgumentError,"Picture cue IDs must be unique" unless cues.map{|cue|cue["id"]}.uniq.length==cues.length
        {"start"=>start,"cues"=>cues}
      end
    end
  end
end
