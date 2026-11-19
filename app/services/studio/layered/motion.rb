# frozen_string_literal: true
module Studio
  module Layered
    module Motion
      PRESETS = %w[sway float drift_left drift_right].freeze
      def self.normalize(raw)
        raise ArgumentError,"Choose a valid layer motion" unless raw.is_a?(Hash) && raw.keys.difference(%w[duration loop keyframes]).empty?
        duration=Composition.number(raw.fetch("duration"),0.25,10)
        looped=raw.fetch("loop",false)
        raise ArgumentError,"Motion loop must be true or false" unless [true,false].include?(looped)
        points=raw.fetch("keyframes")
        raise ArgumentError,"Use 2–12 motion keyframes" unless points.is_a?(Array) && points.length.between?(2,12)
        points=points.map do |point|
          raise ArgumentError,"Use time, X and Y for each keyframe" unless point.is_a?(Hash) && point.keys.sort==%w[t x y]
          {"t"=>Composition.number(point.fetch("t"),0,1),"x"=>Composition.number(point.fetch("x"),-0.3,0.3),"y"=>Composition.number(point.fetch("y"),-0.3,0.3)}
        end
        raise ArgumentError,"Keyframes must run in order from 0 to 1" unless points.first["t"]==0 && points.last["t"]==1 && points.each_cons(2).all? { |a,b| a["t"]<b["t"] }
        if looped && points.first.values_at("x","y")!=points.last.values_at("x","y")
          raise ArgumentError,"A looping motion must end at its starting position"
        end
        {"duration"=>duration,"loop"=>looped,"keyframes"=>points}
      rescue KeyError
        raise ArgumentError,"The layer motion is missing required fields"
      end
      def self.preset(name,amount:0.02,duration:3)
        raise ArgumentError,"Choose an installed motion preset" unless PRESETS.include?(name)
        Composition.number(amount,0,0.3)
        points=case name
        when "sway" then [[0,0,0],[0.25,amount,0],[0.75,-amount,0],[1,0,0]]
        when "float" then [[0,0,0],[0.5,0,-amount],[1,0,0]]
        when "drift_left" then [[0,0,0],[1,-amount,0]]
        when "drift_right" then [[0,0,0],[1,amount,0]]
        end
        normalize({"duration"=>duration,"loop"=>%w[sway float].include?(name),"keyframes"=>points.map { |t,x,y| {"t"=>t,"x"=>x,"y"=>y} }})
      end
      def self.transform(motion,width:,height:,scale:,rotation:)
        angle=rotation*Math::PI/180
        motion.merge("keyframes"=>motion["keyframes"].map do |point|
          x=point["x"]*width*scale;y=point["y"]*height*scale
          point.merge("x"=>x*Math.cos(angle)-y*Math.sin(angle),"y"=>x*Math.sin(angle)+y*Math.cos(angle))
        end)
      end
      # Evaluates both normalized editor tracks and pixel-space flattened tracks.
      def self.offset(motion,time)
        t=motion["loop"] ? time.to_f%motion["duration"]/motion["duration"] : (time.to_f/motion["duration"]).clamp(0,1)
        a,b=motion["keyframes"].each_cons(2).find { |_,right| t<=right["t"] }
        blend=(t-a["t"])/(b["t"]-a["t"])
        %w[x y].map { |axis| a[axis]+(b[axis]-a[axis])*blend }
      end
    end
  end
end
