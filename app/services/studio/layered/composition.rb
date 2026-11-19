# frozen_string_literal: true
module Studio
  module Layered
    module Composition
      ASSETS={"sky.day"=>["Day sky","sky-day.svg"],"sky.night"=>["Night sky","sky-night.svg"],
        "park.ground"=>["Park ground and path","park-ground.svg"],"tree.oak"=>["Oak tree","tree-oak.svg"],
        "bench"=>["Bench","bench.svg"],"character.seated"=>["Seated character illustration","person-seated.svg"]}.freeze
      MAX_LAYERS=24
      def self.number(value,min,max)
        raise ArgumentError,"Scene values must be finite numbers within #{min}–#{max}" unless value.is_a?(Numeric) && value.finite? && value.between?(min,max)
        value
      end
      def self.integer(value,min,max)
        raise ArgumentError,"Scene counts and layer order must be bounded integers" unless value.is_a?(Integer) && value.between?(min,max)
        value
      end
      def self.normalize(raw)
        raise ArgumentError,"Choose a valid 2D composition" unless raw.is_a?(Hash) && raw.keys.difference(%w[version seed canvas camera nodes]).empty? && raw["version"]==1
        raise ArgumentError,"The composition is too large" if JSON.generate(raw).bytesize>64.kilobytes
        canvas=raw.fetch("canvas");camera=raw.fetch("camera",{})
        raise ArgumentError,"Invalid canvas or camera controls" unless canvas.is_a?(Hash) && camera.is_a?(Hash) && canvas.keys.difference(%w[width height fps duration]).empty? && camera.keys.difference(%w[x y]).empty?
        width=integer(canvas.fetch("width"),160,1920);height=integer(canvas.fetch("height"),90,1920)
        raise ArgumentError,"Use even dimensions up to 1920×1080 pixels in area" unless width.even? && height.even? && width*height<=1920*1080
        output={"version"=>1,"seed"=>integer(raw.fetch("seed",0),0,2**32-1),
          "canvas"=>{"width"=>width,"height"=>height,"fps"=>integer(canvas.fetch("fps",24),1,24),"duration"=>number(canvas.fetch("duration",4),1,10)},
          "camera"=>{"x"=>number(camera.fetch("x",0.08),-0.3,0.3),"y"=>number(camera.fetch("y",0),-0.3,0.3)}}
        ids=[];leaves=0;count=0
        visit=lambda do |nodes,level|
          raise ArgumentError,"Use at most four nested asset groups" unless level<=4 && nodes.is_a?(Array)
          nodes.map do |node|
            count+=1
            raise ArgumentError,"Use up to 48 scene nodes" if count>48
            raise ArgumentError,"Invalid scene node" unless node.is_a?(Hash)
            group=node.key?("children")
            allowed=group ? %w[id name children x y scale rotation z_index depth opacity motion] : %w[id name template asset_id x y width height rotation z_index depth opacity fit motion]
            id=node.fetch("id").to_s
            raise ArgumentError,"Scene instances need unique stable identifiers" unless id.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) && !ids.include?(id)
            raise ArgumentError,"Unsupported scene controls" unless node.keys.difference(allowed).empty?
            ids<<id
            result={"id"=>id,"name"=>node.fetch("name",id).to_s.first(120),"z_index"=>integer(node.fetch("z_index",0),-10000,10000),
              "x"=>number(node.fetch("x",group ? 0 : 0.5),-2,2),"y"=>number(node.fetch("y",group ? 0 : 0.5),-2,2),
              "rotation"=>number(node.fetch("rotation",0),-180,180),"opacity"=>number(node.fetch("opacity",1),0,1)}
            result["depth"]=number(node["depth"],0,1) if node.key?("depth")
            result["motion"]=Motion.normalize(node["motion"]) if node.key?("motion")
            if group
              result["scale"]=number(node.fetch("scale",1),0.1,2)
              result["children"]=visit.call(node["children"],level+1)
            else
              leaves+=1
              raise ArgumentError,"Use up to #{MAX_LAYERS} image layers" if leaves>MAX_LAYERS
              raise ArgumentError,"Choose one asset template or library image" unless node.key?("template") != node.key?("asset_id")
              if node.key?("template")
                raise ArgumentError,"Choose an installed 2D asset template" unless ASSETS.key?(node["template"])
                result["template"]=node["template"]
              else
                result["asset_id"]=integer(node["asset_id"],1,2**63-1)
              end
              result["width"]=number(node.fetch("width",0.2),0.01,2)
              result["height"]=number(node.fetch("height",0.3),0.01,2)
              result["fit"]=node.fetch("fit",node.key?("template") ? "stretch" : "contain")
              raise ArgumentError,"Choose contain, cover or stretch" unless %w[contain cover stretch].include?(result["fit"])
            end
            result
          end
        end
        output["nodes"]=visit.call(raw.fetch("nodes"),1)
        layers=flatten(output)
        raise ArgumentError,"Add an image or asset template" if layers.empty?
        area=layers.sum do |layer|
          angle=layer["rotation"]*Math::PI/180
          w=layer["width"];h=layer["height"]
          rw=w*Math.cos(angle).abs+h*Math.sin(angle).abs;rh=w*Math.sin(angle).abs+h*Math.cos(angle).abs
          raise ArgumentError,"An asset is too large for this canvas" if [rw,rh].max>4096
          rw*rh
        end
        raise ArgumentError,"Reduce layer sizes or count to fit the CPU compositing budget" if area>width*height*6
        output
      rescue KeyError,TypeError
        raise ArgumentError,"The composition is missing required scene fields"
      end
      def self.flatten(graph)
        width=graph.fetch("canvas").fetch("width");height=graph.fetch("canvas").fetch("height");output=[]
        visit=lambda do |nodes,x,y,scale,rotation,depth,opacity,motions|
          nodes.each_with_index.sort_by { |node,index| [node.fetch("z_index",0),index] }.each do |node,_|
            angle=rotation*Math::PI/180
            dx=node.fetch("x",0)*width*scale;dy=node.fetch("y",0)*height*scale
            nx=x+dx*Math.cos(angle)-dy*Math.sin(angle);ny=y+dx*Math.sin(angle)+dy*Math.cos(angle)
            nr=rotation+node.fetch("rotation",0);nd=node.fetch("depth",depth);alpha=opacity*node.fetch("opacity",1)
            tracks=motions
            tracks=motions+[Motion.transform(node["motion"],width:width,height:height,scale:scale,rotation:rotation)] if node["motion"]
            if node.key?("children")
              visit.call(node["children"],nx,ny,scale*node.fetch("scale",1),nr,nd,alpha,tracks)
            else
              output<<node.slice("id","name","template","asset_id","fit").merge("x"=>nx,"y"=>ny,
                "width"=>node.fetch("width")*width*scale,"height"=>node.fetch("height")*height*scale,
                "rotation"=>nr,"depth"=>nd,"opacity"=>alpha,"order"=>output.length,"motions"=>tracks)
            end
          end
        end
        visit.call(graph.fetch("nodes"),0,0,1,0,0,1,[])
        output
      end
      def self.displacement(graph,layer,time)
        ratio=time.to_f/graph.fetch("canvas").fetch("duration")
        [-graph.fetch("camera").fetch("x")*graph.fetch("canvas").fetch("width")*layer.fetch("depth")*ratio,
         -graph.fetch("camera").fetch("y")*graph.fetch("canvas").fetch("height")*layer.fetch("depth")*ratio]
      end
      def self.catalog
        ASSETS.map { |key,(name,file)| {key:key,name:name,url:"/lightek/assets2d/#{file}"} }
      end
    end
  end
end
