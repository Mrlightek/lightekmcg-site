# frozen_string_literal: true
module Studio
  module Music
    class Mixer
      EFFECTS={
        "eq"=>{"low"=>[-24,24,0],"mid"=>[-24,24,0],"high"=>[-24,24,0]},
        "compressor"=>{"threshold"=>[-60,0,-24],"ratio"=>[1,20,4],"attack"=>[0.001,1,0.01],"release"=>[0.01,1,0.25],"knee"=>[0,40,20]},
        "distortion"=>{"distortion"=>[0,1,0.3],"wet"=>[0,1,0.5]},
        "delay"=>{"delayTime"=>[0.01,1,0.25],"feedback"=>[0,0.75,0.25],"wet"=>[0,1,0.25]}
      }.freeze
      def self.boolean(value)
        raise ArgumentError,"Mixer switches must be true or false" unless [true,false].include?(value)
        value
      end
      def self.effects(raw)
        raise ArgumentError,"Use at most four inserts per chain" unless raw.is_a?(Array) && raw.length<=4
        result=raw.map do |effect|
          raise ArgumentError,"Effect inserts must be objects" unless effect.is_a?(Hash)
          kind=effect.fetch("kind");spec=EFFECTS[kind] || raise(ArgumentError,"Choose EQ, compressor, distortion or delay")
          params=effect.fetch("params",{})
          raise ArgumentError,"Unknown effect parameters" unless params.is_a?(Hash) && (params.keys-spec.keys).empty?
          {"id"=>Patterns.id(effect.fetch("id")),"kind"=>kind,"enabled"=>boolean(effect.fetch("enabled",true)),
            "params"=>spec.to_h{|key,(low,high,default)|[key,Composition.number(params.fetch(key,default),low,high)]}}
        end
        raise ArgumentError,"Effect IDs must be unique within a chain" unless result.map{|e|e["id"]}.uniq.length==result.length
        result
      end
      def self.normalize(data,tracks:,raw_tracks:,version:)
        raise ArgumentError,"Mixer buses and inserts require music source version 4" if version<4
        raw=data.fetch("mixer",{})
        raise ArgumentError,"Mixer must be an object" unless raw.is_a?(Hash)
        buses=raw.fetch("buses",[]);master=raw.fetch("master",{})
        raise ArgumentError,"Use at most eight mixer buses" unless buses.is_a?(Array) && buses.length<=8
        raise ArgumentError,"Master mix must be an object" unless master.is_a?(Hash)
        buses=buses.map do |bus|
          raise ArgumentError,"Mixer buses must be objects" unless bus.is_a?(Hash)
          raise ArgumentError,"Buses feed the master directly" if (bus.keys & %w[output bus_id]).any?
          {"id"=>Patterns.id(bus.fetch("id")),"name"=>bus.fetch("name","Group").to_s.first(60),
            "gain"=>Composition.number(bus.fetch("gain",1),0,1.5),"pan"=>Composition.number(bus.fetch("pan",0),-1,1),
            "muted"=>boolean(bus.fetch("muted",false)),"solo"=>boolean(bus.fetch("solo",false)),"effects"=>effects(bus.fetch("effects",[]))}
        end
        raise ArgumentError,"Mixer bus IDs must be unique" unless buses.map{|b|b["id"]}.uniq.length==buses.length
        tracks.zip(raw_tracks).each do |track,source|
          route=source["bus_id"]
          raise ArgumentError,"Choose an existing mixer bus" unless route.nil? || buses.any?{|b|b["id"]==route}
          track.merge!("bus_id"=>route,"effects"=>effects(source.fetch("effects",[])))
        end
        result={"buses"=>buses,"master"=>{"gain"=>Composition.number(master.fetch("gain",1),0,1.5),"effects"=>effects(master.fetch("effects",[]))}}
        count=tracks.sum{|t|t["effects"].length}+buses.sum{|b|b["effects"].length}+result["master"]["effects"].length
        raise ArgumentError,"Use at most 32 inserts across the song" if count>32
        result
      end
    end
  end
end
