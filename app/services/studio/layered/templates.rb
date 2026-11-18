# frozen_string_literal: true
module Studio
  module Layered
    module Templates
      def self.asset(id,key,x,y,width,height,z=0)
        {"id"=>id,"name"=>Composition::ASSETS.fetch(key).first,"template"=>key,"x"=>x,"y"=>y,"width"=>width,"height"=>height,"z_index"=>z}
      end
      def self.park(seed:,night:false,trees:nil,benches:nil,character:false,pan:0.08)
        random=Random.new(seed)
        trees=trees.nil? ? random.rand(3..5) : Composition.integer(trees,0,8)
        benches=benches.nil? ? random.rand(1..2) : Composition.integer(benches,1,3)
        far=[];near=[]
        trees.times do |index|
          foreground=index>=trees-([trees,2].min)
          if foreground
            x=near.empty? ? -0.015 : 1.015
            near<<asset("tree-#{index+1}","tree.oak",x,0.53,0.3,0.91,index)
          else
            slots=[0.12,0.33,0.76,0.93,0.43,0.62]
            far<<asset("tree-#{index+1}","tree.oak",slots[index]+random.rand(-0.02..0.02),0.51,0.12+random.rand*0.03,0.4+random.rand*0.08,index)
          end
        end
        furniture=[]
        benches.times do |index|
          x=[0.58,0.83,0.28][index]
          furniture<<asset("bench-#{index+1}","bench",x,0.77,0.29,0.22,index)
        end
        furniture<<asset("character-1","character.seated",0.58,0.673,0.091,0.29,10) if character
        Composition.normalize({"version"=>1,"seed"=>seed,"canvas"=>{"width"=>640,"height"=>360,"fps"=>24,"duration"=>4},"camera"=>{"x"=>pan,"y"=>0},"nodes"=>[
          {"id"=>"environment","name"=>"Environment","z_index"=>0,"depth"=>0,"children"=>[asset("sky",night ? "sky.night" : "sky.day",0.5,0.5,1.04,1.04)]},
          {"id"=>"background","name"=>"Background trees","z_index"=>10,"depth"=>0.16,"children"=>far},
          {"id"=>"ground","name"=>"Ground and path","z_index"=>20,"depth"=>0.25,"children"=>[asset("path","park.ground",0.5,0.81,1.2,0.51)]},
          {"id"=>"midground","name"=>"Benches and characters","z_index"=>30,"depth"=>0.48,"children"=>furniture},
          {"id"=>"foreground","name"=>"Foreground trees","z_index"=>40,"depth"=>0.9,"children"=>near}]})
      end
    end
  end
end
