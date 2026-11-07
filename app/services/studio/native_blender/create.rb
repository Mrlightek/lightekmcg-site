# frozen_string_literal: true
module Studio
  module NativeBlender
    # Bounded procedural authoring without credentials or generated Python.
    class Create
      RECIPES = {
        "cube"=>["Cube","geometry"], "sphere"=>["Sphere","geometry"],
        "cylinder"=>["Cylinder","geometry"], "plane"=>["Plane","geometry"],
        "tpl_live_interview"=>["Interview stage","sets"], "env_memory_chamber"=>["Modular room","sets"],
        "env_rooftop"=>["Rooftop stage","sets"], "arch_glasshouse"=>["Glasshouse","sets"],
        "light_warm_practical"=>["Three-light rig","lights"], "fx_memory_fragment"=>["Animated fragments","effects"]
      }.freeze
      def self.items = RECIPES.map { |key,(name,category)| {key:key,name:name,category:category} }
      def self.call(access:,payload:) = new(access,payload).call
      def initialize(access,payload) = (@access,@payload=access,payload)
      def call
        recipe=@payload.fetch("recipe").to_s
        raise ArgumentError,"Choose a built-in Studio asset" unless RECIPES.key?(recipe)
        key=@payload.fetch("request_key").to_s
        raise ArgumentError,"A creation request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        size=Float(@payload.fetch("size",1))
        raise ArgumentError,"Size must be between 0.01 and 100" unless size.finite? && size.between?(0.01,100)
        hex=@payload.fetch("color","#508bb8").to_s
        raise ArgumentError,"Choose a six-digit surface color" unless hex.match?(/\A#[0-9a-fA-F]{6}\z/)
        rgba=hex.delete_prefix("#").scan(/../).map { |part| part.to_i(16)/255.0 }+[1]
        roughness=Float(@payload.fetch("roughness",0.5));metallic=Float(@payload.fetch("metallic",0))
        raise ArgumentError,"Material values must be between 0 and 1" unless [roughness,metallic].all? { |v| v.finite? && v.between?(0,1) }
        name=(@payload["name"].presence || RECIPES[recipe].first).to_s.first(120)
        @access.user.with_lock do
          if @payload["scene_id"].present?
            scene=@access.scene!(@payload["scene_id"])
            scene.with_lock do
              journal=scene.settings.fetch("creation_requests",{})
              if journal[key]
                raise ArgumentError,"Request key belongs to another asset" unless journal[key]["recipe"]==recipe
                return journal[key]
              end
              scene.lock_version=Integer(@payload.fetch("lock_version"))
              result=populate(scene,recipe,name,size,rgba,roughness,metallic)
              scene.update!(settings:scene.settings.merge("creation_requests"=>journal.to_a.last(99).to_h.merge(key=>result)))
              result.merge("lock_version"=>scene.lock_version)
            end
          else
            project=StudioProject.find_by(owner_id:@access.user.id,request_key:key)
            if project
              raise ArgumentError,"Request key belongs to another production" unless project.site_id==@access.site_id && project.description=="Studio built-in: #{recipe}"
              return {"project_id"=>project.id,"scene_id"=>project.studio_scenes.first.id}
            end
            project=StudioProject.create!(owner:@access.user,site_id:@access.site_id,name:name,request_key:key,description:"Studio built-in: #{recipe}")
            scene=project.studio_scenes.first
            result=populate(scene,recipe,name,size,rgba,roughness,metallic)
            add(scene,Studio::Library::Catalog.cameras,"production_rig") unless scene.scene_objects.exists?(object_type:"camera")
            add(scene,Studio::Library::Catalog.lights,"production_rig") unless scene.scene_objects.where(object_type:%w[area_light point_light]).exists?
            scene.update!(name:name,settings:scene.settings.merge("active_camera"=>scene.scene_objects.find_by(object_type:"camera").name))
            result
          end
        end
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before adding an asset."
      end
      def populate(scene,recipe,name,size,rgba,roughness,metallic)
        objects=if %w[cube sphere cylinder plane].include?(recipe)
          [Studio::Library::Catalog.mesh(name,recipe,[0,0,recipe=="plane" ? 0 : 1],[1,1,1])]
        else
          Studio::Library::Catalog.objects(recipe).deep_dup
        end
        objects.each do |item|
          d=item["definition"]
          %w[location scale].each { |axis| d[axis]=d[axis].map { |v| v*size } if d[axis] }
          Array(d.dig("animation","frames")).each { |frame| frame["location"]=frame["location"].map { |v| v*size } if frame["location"] }
          d["material"]=(d["material"]||{}).merge("color"=>rgba,"roughness"=>roughness,"metallic"=>metallic) if %w[cube sphere cylinder plane].include?(item["type"])
        end
        ids=add(scene,objects,recipe)
        {"project_id"=>scene.studio_project_id,"scene_id"=>scene.id,"object_ids"=>ids,"object_id"=>ids.first,"recipe"=>recipe}
      end
      def add(scene,items,recipe)
        position=scene.scene_objects.maximum(:position).to_i
        items.each_with_index.map do |item,index|
          scene.scene_objects.create!(name:item["name"],object_type:item["type"],position:position+index+1,
            definition:{"location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1]}.merge(item["definition"]).merge("studio_builtin"=>recipe)).id
        end
      end
    end
  end
end
