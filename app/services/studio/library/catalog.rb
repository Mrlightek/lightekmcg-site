# frozen_string_literal: true
module Studio
  module Library
    # Executable, server-owned recipes. These are production blocking assets,
    # not claims that finished character models or licensed stock media exist.
    class Catalog
      ITEMS = [
        ["tpl_single_camera_drama", "Single-Camera Drama", "templates", "A saved 50mm camera, warm key/fill lights and two blocking actors.", "scene"],
        ["tpl_live_interview", "Live Interview Package", "templates", "Two blocking guests, interview desk, cameras, lights and a lower-third image.", "scene"],
        ["tpl_night_exterior", "Atlanta Night Exterior", "templates", "Procedural rooftop, city silhouettes and warm night lighting.", "scene"],
        ["col_void_echo_pilot", "Void Echo — Pilot Kit", "collections", "Blocking cast, memory chamber, interface prop, camera and generated pulse bed.", "scene"],
        ["col_broadcast", "Late Night Broadcast Kit", "collections", "Desk, guest blocking, cameras, lighting, generated audio and lower-third image.", "scene"],
        ["char_iris", "Iris", "characters", "Editable primitive mannequin for Iris's staging and shot blocking.", "scene"],
        ["char_marcus", "Marcus", "characters", "Editable primitive mannequin for Marcus's staging and shot blocking.", "scene"],
        ["env_memory_chamber", "Echo Memory Chamber", "environments", "Modular walls, floor and cyan interface blocks for scene blocking.", "scene"],
        ["env_rooftop", "Atlanta Rooftop", "environments", "Rooftop deck, parapets and a procedural skyline.", "scene"],
        ["prop_echo_interface", "Echo Neural Interface", "props", "Editable geometric interface prop with metallic and glass surfaces.", "scene"],
        ["prop_phone", "Hero Phone", "props", "Editable phone body and screen for shot blocking.", "scene"],
        ["vehicle_night_sedan", "Night Sedan", "vehicles", "Procedural sedan body, cabin and wheels for blocking.", "scene"],
        ["arch_glasshouse", "Glasshouse Residence", "architecture", "Modular floor, columns, roof and translucent wall panels.", "scene"],
        ["cam_intimate_50", "Intimate 50mm Coverage", "cameras", "Three saved 50mm camera positions for medium and close coverage.", "scene"],
        ["light_warm_practical", "Warm Practical Rig", "lights", "Warm key, soft fill and practical point light with saved energy values.", "scene"],
        ["mat_worn_brass", "Worn Brass", "materials", "Apply a brass color, metallic surface and rough finish to a selected primitive.", "object"],
        ["mat_memory_glass", "Memory Glass", "materials", "Apply a translucent, transmissive material to a selected primitive.", "object"],
        ["geo_city_block", "Modular City Block", "geometry_systems", "Generate a deterministic block of six editable buildings.", "scene"],
        ["fx_memory_fragment", "Memory Fragmentation", "fx", "Eight animated geometric fragments with a two-second dispersal loop.", "scene"],
        ["audio_neural_pulse", "Neural Pulse Bed", "audio", "Generate a reusable four-second WAV pulse bed and place it on the timeline.", "timeline"],
        ["gfx_lower_thirds", "Lightek Lower Third System", "graphics", "Generate a transparent PNG title/guest graphic and place it on the timeline.", "timeline"],
        ["anim_walk_neutral", "Neutral Walk Cycle", "animations", "A two-second procedural blocking gait for a library mannequin, or a bob/advance loop for a selected object.", "object"]
      ].map { |key,name,category,description,target| {"key"=>key,"name"=>name,"category"=>category,"description"=>description,"target"=>target} }.freeze
      def self.items = ITEMS.map(&:dup)
      def self.fetch(key) = ITEMS.find { |item| item["key"] == key } || raise(ArgumentError, "Choose an available library recipe")
      def self.material(key)
        key == "mat_worn_brass" ? {"color"=>[0.58,0.36,0.12,1],"metallic"=>0.85,"roughness"=>0.48} :
          {"color"=>[0.25,0.75,0.85,0.35],"metallic"=>0.0,"roughness"=>0.12,"transmission"=>0.85}
      end
      def self.objects(key)
        case key
        when "char_iris" then mannequin("Iris", -1.2, [0.25,0.65,0.7,1])
        when "char_marcus" then mannequin("Marcus", 1.2, [0.65,0.35,0.2,1])
        when "cam_intimate_50" then cameras
        when "light_warm_practical" then lights
        when "geo_city_block" then city
        when "env_rooftop", "tpl_night_exterior" then rooftop + city + (key.start_with?("tpl") ? cameras + lights : [])
        when "env_memory_chamber" then chamber
        when "arch_glasshouse" then glasshouse
        when "prop_phone" then [mesh("Phone body", "cube", [0,0,1.2],[0.38,0.06,0.75]), mesh("Phone screen", "cube", [0,-0.065,1.2],[0.33,0.01,0.65],[0.1,0.45,0.65,1])]
        when "prop_echo_interface" then [mesh("Interface pedestal", "cylinder", [0,0,0.5],[0.7,0.7,0.5]), mesh("Interface glass", "sphere", [0,0,1.3],[0.5,0.5,0.5],[0.25,0.75,0.85,0.35]).tap { |o| o["definition"]["material"] = material("mat_memory_glass") }]
        when "vehicle_night_sedan" then sedan
        when "fx_memory_fragment" then fragments
        when "tpl_single_camera_drama" then objects("char_iris") + objects("char_marcus") + cameras + lights
        when "tpl_live_interview", "col_broadcast" then objects("char_iris") + objects("char_marcus") + [mesh("Interview desk", "cube", [0,-1,0.8],[2,0.5,0.8])] + cameras + lights
        when "col_void_echo_pilot" then objects("char_iris") + objects("char_marcus") + chamber + objects("prop_echo_interface") + cameras + lights
        else []
        end
      end
      def self.mesh(name,type,location,scale,color=[0.3,0.36,0.44,1])
        {"name"=>name,"type"=>type,"definition"=>{"location"=>location,"rotation"=>[0,0,0],"scale"=>scale,"material"=>{"color"=>color,"roughness"=>0.6}}}
      end
      def self.mannequin(name,x,color)
        [["Head","sphere",[x,0,2.5],[0.25,0.25,0.3]], ["Torso","cube",[x,0,1.8],[0.3,0.18,0.4]],
         ["Left arm","cylinder",[x-0.45,0,1.8],[0.1,0.1,0.4]], ["Right arm","cylinder",[x+0.45,0,1.8],[0.1,0.1,0.4]],
         ["Left leg","cylinder",[x-0.18,0,0.8],[0.13,0.13,0.5]], ["Right leg","cylinder",[x+0.18,0,0.8],[0.13,0.13,0.5]]].map do |part,type,loc,scale|
          mesh("#{name} · #{part}",type,loc,scale,color).tap { |object| object["definition"]["body_part"] = part.downcase; object["definition"]["character_key"] = name.downcase }
        end
      end
      def self.cameras
        [["Medium",[6,-8,4]],["Close left",[-3,-5,2.5]],["Close right",[3,-5,2.5]]].map { |name,loc| {"name"=>"50mm · #{name}","type"=>"camera","definition"=>{"location"=>loc,"rotation"=>[72,0,0],"scale"=>[1,1,1],"lens"=>50,"look_at"=>[0,0,1.5]}} }
      end
      def self.lights
        [{"name"=>"Warm key","type"=>"area_light","definition"=>{"location"=>[3,-4,5],"energy"=>1000,"size"=>4,"color"=>[1,0.7,0.4],"look_at"=>[0,0,1]}},
         {"name"=>"Soft fill","type"=>"area_light","definition"=>{"location"=>[-3,-2,4],"energy"=>450,"size"=>5,"color"=>[0.6,0.75,1],"look_at"=>[0,0,1]}},
         {"name"=>"Warm practical","type"=>"point_light","definition"=>{"location"=>[0,2,2],"energy"=>160,"color"=>[1,0.55,0.2]}}]
      end
      def self.city
        6.times.map { |i| mesh("City building #{i+1}","cube",[(i-2.5)*3,8,2+i%3],[1,1,2+i%3],[0.12+0.03*i,0.16,0.23,1]) }
      end
      def self.rooftop
        [mesh("Rooftop deck","cube",[0,0,-0.2],[7,5,0.2]),mesh("Parapet left","cube",[-7,0,0.6],[0.15,5,0.6]),mesh("Parapet back","cube",[0,5,0.6],[7,0.15,0.6])]
      end
      def self.chamber
        [mesh("Chamber floor","cube",[0,0,-0.15],[5,5,0.15]),mesh("Chamber back","cube",[0,5,2.5],[5,0.15,2.5]),mesh("Chamber side","cube",[-5,0,2.5],[0.15,5,2.5]),mesh("Memory display","cube",[0,4.7,2],[2,0.1,1],[0.15,0.7,0.8,1])]
      end
      def self.glasshouse
        [mesh("Residence floor","cube",[0,0,-0.1],[4,3,0.1]),mesh("Residence roof","cube",[0,0,4],[4,3,0.1])] +
          [-4,4].product([-3,3]).map { |x,y| mesh("Column #{x},#{y}","cube",[x,y,2],[0.12,0.12,2]) } +
          [mesh("Glass wall","cube",[0,3,2],[4,0.05,2]).tap { |o| o["definition"]["material"] = material("mat_memory_glass") }]
      end
      def self.sedan
        [mesh("Sedan body","cube",[0,0,0.8],[1.1,2.3,0.4],[0.06,0.07,0.1,1]),mesh("Sedan cabin","cube",[0,0,1.5],[0.9,1.2,0.4],[0.12,0.2,0.28,1])] +
          [-1.1,1.1].product([-1.5,1.5]).map { |x,y| mesh("Wheel #{x},#{y}","cylinder",[x,y,0.5],[0.45,0.45,0.2],[0.02,0.02,0.02,1]).tap { |o| o["definition"]["rotation"] = [0,90,0] } }
      end
      def self.fragments
        8.times.map do |i|
          loc=[(i%4-1.5)*0.6,0,1+i/4.0]
          mesh("Memory fragment #{i+1}","cube",loc,[0.2,0.12,0.2],[0.15,0.7,0.8,1]).tap do |o|
            o["definition"]["animation"]={"fps"=>24,"frames"=>[{"frame"=>1,"location"=>loc},{"frame"=>25,"location"=>[loc[0]*3,1+i*0.2,loc[2]*1.6]},{"frame"=>49,"location"=>loc}]}
          end
        end
      end
    end
  end
end
