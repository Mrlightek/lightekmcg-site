# frozen_string_literal: true
require "json"
require "digest"
module Studio
  module NativeBlender
    # Original JSON remains intact; this adapter compiles both historical pack
    # schemas to a bounded, declarative Blender manifest. No template code runs.
    class MediaPresets
      PATH=File.expand_path("../../../../config/studio/packs/original_media.json",__dir__)
      PROJECT_TYPES=%w[production_preset industry_pack show_bible broadcast_package].freeze
      ASSET_TYPES=%w[rig_profile blend_library asset_library audio_pack audio_package character_rig scene_template demo_ingest_recipe import_recipe].freeze
      def self.records = (@records ||= JSON.parse(File.read(PATH)))
      def self.fetch(key) = records.find { |item| item["key"]==key } || raise(ArgumentError,"Choose an available JSON media preset")
      def self.resolve(key, stack=[])
        raise ArgumentError,"Cyclic template inheritance" if stack.include?(key) || stack.length>12
        record=fetch(key);value=record.fetch("definition")
        Array(value["inherits"]).reduce({}) { |result,parent| result.deep_merge(resolve(parent,stack+[key])) }.deep_merge(value)
      end
      def self.items
        records.map do |record|
          data=resolve(record["key"]);kind=data["kind"] || data["type"] || "industry_pack"
          {"key"=>record["key"],"name"=>data["title"].presence || record["key"].tr("_/","  ").titleize,
           "category"=>kind,"project_template"=>PROJECT_TYPES.include?(kind),"requires_asset"=>ASSET_TYPES.include?(kind),
           "output_summary"=>summary(record["key"]),"source_archive"=>record["source_archive"],"source_sha256"=>record["source_sha256"],"description"=>description(kind)}
        end
      end
      def self.summary(key)
        plan=compile(key);outputs=[]
        outputs<<"Editable scene objects" if plan["objects"].any?
        {"markers"=>"Timeline markers", "texts"=>"Blender text objects", "nodes"=>"Compositor nodes", "materials"=>"Material datablocks", "geometry_groups"=>"Geometry Nodes groups"}.each { |field,label| outputs<<label if Array(plan["directives"][field]).any? }
        outputs<<"Render settings" if plan["settings"].any?
        outputs<<"Original brief / instructions saved in Blender Text Editor"
        outputs
      end
      def self.description(kind)
        return "Choose a prepared native Blender or audio asset to supply the original template's media dependency." if ASSET_TYPES.include?(kind)
        return "Create a production, add its scenes to a project, or apply its Blender setup to a saved scene." if PROJECT_TYPES.include?(kind)
        return "Keep workflow rules and creative instructions with the project and in Blender's Text Editor." if %w[voice_music audio_profile asset_ingest action_pack training_policy report_schema].include?(kind)
        "Apply this original JSON definition as a reusable Blender #{kind.tr('_',' ')} preset."
      end
      def self.segments(data)
        data["shot_plan"] || data.dig("show_bible","segments") || Array(data["episodes"]).flat_map { |episode| episode["segments"] || [] }.presence ||
          data["segments"] || data.dig("config","segments") || data.dig("config","structure") || [data["title"] || "Scene 1"]
      end
      def self.compile(key, title:nil)
        data=resolve(key);kind=data["kind"] || data["type"] || "industry_pack"
        config=(data["body"] || {}).deep_merge(data["config"] || {})
        plan={"objects"=>[],"settings"=>{},"directives"=>{"key"=>key,"title"=>title.presence || data["title"].presence || key,"definition"=>data,"markers"=>[],"texts"=>[],"nodes"=>[]},"kind"=>kind}
        camera=data["camera"].is_a?(Hash) ? data["camera"] : config["camera"].is_a?(Hash) ? config["camera"] : {}
        camera=config.merge(camera).merge(data.except("config","body","camera")) if kind.start_with?("camera")
        if kind.start_with?("camera") || PROJECT_TYPES.include?(kind)
          c=camera_definition(camera,config,data)
          plan["objects"]<<{"name"=>"#{key} · Camera","type"=>"camera","definition"=>c}
        end
        if PROJECT_TYPES.include?(kind) || %w[geometry_set].include?(kind)
          generator=config["scene_generator"].to_s.presence || data.dig("set","type").to_s.presence || key
          recipe=generator.match?(/sport|desk/) ? "tpl_live_interview" : generator.match?(/night|city/) ? "tpl_night_exterior" : "tpl_single_camera_drama"
          geometry=Studio::Library::Catalog.objects(recipe).reject { |object| object["type"]=="camera" }
          plan["objects"].concat(geometry)

        end
        plan["directives"]["geometry_groups"]=data["node_groups"] if kind=="geometry_nodes_pack"
        if kind=="geometry_set"
          plan["objects"]=Array(config["primitives"]).each_with_index.flat_map do |primitive,index|
            x=(index-1)*2.5
            case primitive
            when "podium" then [Studio::Library::Catalog.mesh("Podium #{index+1}","cube",[x,0,0.75],[0.6,0.5,0.75])]
            when "led_wall", "stadium_backdrop" then [Studio::Library::Catalog.mesh("LED backdrop","cube",[0,4,2.5],[5,0.15,2.5],[0.03,0.1,0.5,1])]
            when "broadcast_desk" then [Studio::Library::Catalog.mesh("Broadcast desk","cube",[0,0,0.8],[2.25,0.7,0.8])]
            when "confessional_chair" then [Studio::Library::Catalog.mesh("Chair seat","cube",[0,0,0.6],[0.7,0.7,0.15]),Studio::Library::Catalog.mesh("Chair back","cube",[0,0.6,1.2],[0.7,0.15,0.7])]
            else []
            end
          end
        end
        if kind=="material" || kind=="material_catalog" || kind=="material_style"
          names=Array(data["materials"]);names=[config["catalog_key"] || key] if names.empty?
          plan["directives"]["materials"]=names.map { |name| {"name"=>name,"color"=>material_color(name),"metallic"=>name.match?(/metal|brushed/i) ? 0.8 : 0.0,"roughness"=>name.match?(/gloss|floor/i) ? 0.15 : 0.55} }
        end
        render=config["render_defaults"] || (kind=="format" ? config : {})
        resolution=render["resolution"]
        resolution=resolution.split('x').map(&:to_i) if resolution.is_a?(String)
        resolution=[1080,1920] if !resolution && (config["delivery"]=="vertical" || config["format"].to_s.include?("vertical"))
        if resolution
          raise ArgumentError,"Invalid preset resolution" unless resolution.length==2 && resolution.all? { |v| v.to_i.between?(64,4096) }
          plan["settings"].merge!("resolution_x"=>resolution[0].to_i,"resolution_y"=>resolution[1].to_i)
        end
        fps=Float(render.fetch("fps",24));raise ArgumentError,"Invalid preset FPS" unless fps.finite? && fps.between?(1,120)
        plan["settings"].merge!("fps"=>fps.ceil,"fps_base"=>fps.ceil/fps) if render.any?
        if kind.include?("timeline") || kind=="show_bible"
          beats=config["beats"] || config["shots"] || segments(data)
          cursor=1
          Array(beats).first(100).each do |beat|
            name=beat.is_a?(Hash) ? beat["name"] || beat["slug"] : beat.to_s
            seconds=beat.is_a?(Hash) ? beat.fetch("duration_seconds",5) : config.dig("cadence",name) || 5
            frames=(Float(seconds)*fps).round.clamp(1,216000)
            plan["directives"]["markers"]<<{"name"=>name.to_s.first(100),"frame"=>cursor};cursor+=frames
          end
          plan["settings"].merge!("frame_start"=>1,"frame_current"=>1,"frame_end"=>[cursor-1,1].max)
        end
        if kind.match?(/graphic|overlay|title|brand/)
          graphic=data["graphics"] || config
          score=graphic["scorebug"]
          text=score.is_a?(Hash) ? score["text"] || "#{score['home_abbr'] || 'HOME'} #{score['home_score'] || 0} - #{score['away_score'] || 0} #{score['away_abbr'] || 'AWAY'}" : kind.include?("brand") ? data["title"] || "LIGHTEK" : "#{title.presence || data['title'].presence || 'LIGHTEK LIVE'}"
          plan["directives"]["texts"]<<{"body"=>text.first(200),"color"=>[0.85,0.7,0.35,1]}
        end
        nodes=data["nodes"] || config["compositor_nodes"]
        nodes=%w[Glare ColorBalance] if !nodes && kind.match?(/style|broadcast_package/)
        plan["directives"]["nodes"]=Array(nodes).map(&:to_s).first(20)
        plan["settings"]["render_engine"]="CYCLES" if plan["directives"]["nodes"].any?
        # Compose explicit references from the original pack rather than
        # reducing an industry package to a label.
        %w[brand_system geometry_nodes_pack].each do |reference|
          child_key=data[reference]
          next unless child_key.is_a?(String) && records.any? { |record| record["key"]==child_key }
          child=compile(child_key,title:title)
          %w[texts nodes materials geometry_groups].each do |field|
            values=Array(child["directives"][field]);next if values.empty?
            plan["directives"][field]=Array(plan["directives"][field])+values
          end
        end
        plan
      end
      def self.material_color(name)
        return [0.02,0.025,0.03,1] if name.match?(/black/i)
        return [0.04,0.1,0.8,1] if name.match?(/blue|led/i)
        return [0.7,0.03,0.03,1] if name.match?(/red/i)
        return [0.06,0.35,0.09,1] if name.match?(/turf/i)
        [0.35,0.4,0.45,1]
      end
      def self.camera_definition(raw,config,data)
        dof=raw["dof"].is_a?(Hash) ? raw["dof"] : {}
        settings=CameraSettings.normalize({"lens"=>raw["lens"] || raw["lens_mm"] || raw["focal_length"] || 50,
          "sensor_width"=>raw["sensor_width"] || raw["sensor_width_mm"] || 36,
          "dof_enabled"=>raw["use_dof"] || raw["depth_of_field"] || dof["enabled"] || raw["dof"]==true,
          "aperture_fstop"=>raw["fstop"] || raw["f_stop"] || dof["fstop"] || 2.8})
        loc=raw["location"] || [0,-8,2.5]
        rotation=raw["rotation_euler"] ? raw["rotation_euler"].map { |v| v.to_f*180/Math::PI } : [80,0,0]
        settings.merge!("location"=>loc,"rotation"=>rotation,"scale"=>[1,1,1],"look_at"=>[0,0,1.5])
        move=raw["movement"] || raw["style"] || raw["move"] || config.dig("shots","camera") || data["camera_grammar"]
        unless move.to_s.match?(/lockoff|locked_off|interview|wide_stage/) || move.blank?
          ending=loc.each_with_index.map { |v,i| v.to_f+(i==1 ? 1.0 : 0) }
          settings["animation"]={"frames"=>[{"frame"=>1,"location"=>loc},{"frame"=>49,"location"=>ending}],"fps"=>24}
        end
        settings
      end
    end
  end
end
