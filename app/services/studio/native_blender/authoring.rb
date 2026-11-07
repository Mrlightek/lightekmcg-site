# frozen_string_literal: true
module Studio
  module NativeBlender
    class Authoring
      KINDS=%w[mesh_translate mesh_extrude mesh_subdivide mesh_inset mesh_bevel mesh_delete mesh_merge mesh_smooth sculpt modifier bone_pose bone_add weight shape_key keyframe node_add node_link node_value node_remove].freeze
      NODES={
        "material"=>%w[ShaderNodeBsdfPrincipled ShaderNodeOutputMaterial ShaderNodeTexNoise ShaderNodeTexVoronoi ShaderNodeTexChecker ShaderNodeTexCoord ShaderNodeMapping ShaderNodeValToRGB ShaderNodeMixRGB ShaderNodeMath ShaderNodeBump ShaderNodeNormalMap ShaderNodeEmission ShaderNodeMixShader ShaderNodeBsdfTransparent ShaderNodeRGB ShaderNodeValue],
        "geometry"=>%w[NodeGroupInput NodeGroupOutput GeometryNodeTransform GeometryNodeMeshCube GeometryNodeMeshUVSphere GeometryNodeSetPosition GeometryNodeInputPosition GeometryNodeJoinGeometry GeometryNodeSubdivisionSurface GeometryNodeSetMaterial GeometryNodeInstanceOnPoints GeometryNodeRealizeInstances GeometryNodeDistributePointsOnFaces ShaderNodeMath ShaderNodeVectorMath ShaderNodeTexNoise ShaderNodeValue],
        "compositor"=>%w[CompositorNodeRLayers CompositorNodeComposite CompositorNodeGlare CompositorNodeBlur CompositorNodeMixRGB CompositorNodeColorBalance CompositorNodeLensdist CompositorNodeAlphaOver CompositorNodeBrightContrast CompositorNodeHueSat CompositorNodeRGB CompositorNodeValue]
      }.freeze
      def self.call(access:,payload:) = new(access,payload).call
      def initialize(access,payload) = (@access,@payload=access,payload)
      def call
        scene=@access.scene!(@payload.fetch("scene_id"));result=nil
        key=@payload.fetch("request_key").to_s
        raise ArgumentError,"An authoring request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        scene.with_lock do
          receipts=scene.settings.fetch("authoring_receipts",{})
          return receipts[key] if receipts[key]
          scene.lock_version=Integer(@payload.fetch("lock_version"))
          history=scene.settings.fetch("authoring_history",[]).deep_dup
          redo_stack=scene.settings.fetch("authoring_redo",[]).deep_dup
          operation=@payload.fetch("operation","apply")
          if %w[undo redo].include?(operation)
            entry=(operation=="undo" ? history : redo_stack).pop
            raise ArgumentError,"No authoring edit to #{operation}" unless entry
            object=scene.scene_objects.find(entry.fetch("object_id"))
            commands=Array(object.definition["authoring_commands"]).deep_dup
            if operation=="undo"
              raise ArgumentError,"Authoring history changed. Refresh the scene." unless commands.last==entry["command"]
              commands.pop;redo_stack<<entry
            else
              commands<<entry["command"];history<<entry
            end
          elsif operation=="apply"
            object=scene.scene_objects.find(@payload.fetch("object_id"))
            raise ArgumentError,"Select an editable scene element" if object.definition["native_source_preview"] || object.definition["native_deleted"]
            command=normalize(@payload.fetch("command").to_h.deep_stringify_keys,object)
            commands=Array(object.definition["authoring_commands"]).deep_dup+[command]
            history<<{"object_id"=>object.id,"command"=>command};redo_stack=[]
          else
            raise ArgumentError,"Choose apply, undo or redo"
          end
          raise ArgumentError,"Save and reopen the Blender asset after 128 edits to this object" if commands.length>128 || commands.to_json.bytesize>256000
          object.update!(definition:object.definition.merge("authoring_commands"=>commands))
          revision=scene.settings.fetch("native_revision",0).to_i+1
          result={"scene_id"=>scene.id,"object_id"=>object.id,"lock_version"=>scene.lock_version+1,"native_revision"=>revision,"command_count"=>commands.length}
          scene.update!(settings:scene.settings.merge("authoring_history"=>history.last(128),"authoring_redo"=>redo_stack.last(128),"native_revision"=>revision,"authoring_receipts"=>receipts.to_a.last(99).to_h.merge(key=>result)))
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before applying an edit."
      end
      def number(value,min=-1000000,max=1000000)
        n=Float(value);raise ArgumentError,"Use a finite value from #{min} to #{max}" unless n.finite? && n.between?(min,max);n
      end
      def integer(value,min,max)
        n=Integer(value);raise ArgumentError,"Integer outside its range" unless n.between?(min,max);n
      end
      def vector(value,count=3)
        raise ArgumentError,"Use #{count} numeric values" unless value.is_a?(Array) && value.length==count
        value.map { |v| number(v) }
      end
      def name(value)
        text=value.to_s;raise ArgumentError,"Use a name with 1–120 characters" unless text.length.between?(1,120) && !text.include?("\0");text
      end
      def normalize(raw,object)
        kind=raw.fetch("kind");raise ArgumentError,"Unsupported authoring tool" unless KINDS.include?(kind)
        type=object.definition["native_type"] || object.object_type.upcase
        mesh=%w[MESH CUBE SPHERE CYLINDER PLANE].include?(type)
        raise ArgumentError,"Select a mesh for this tool" if (kind.start_with?("mesh_") || %w[sculpt weight shape_key modifier].include?(kind)) && !mesh
        raise ArgumentError,"Select an armature for rigging" if kind.start_with?("bone_") && type!="ARMATURE"
        cmd={"kind"=>kind}
        if kind.start_with?("mesh_") || kind=="weight"
          ids=raw.fetch("indices",[]);raise ArgumentError,"Select up to 4096 elements" unless ids.is_a?(Array) && ids.length<=4096
          cmd["indices"]=ids.map { |i| integer(i,0,10000000) }.uniq
          raise ArgumentError,"Select vertices for weights" if kind=="weight" && cmd["indices"].empty?
        end
        case kind
        when "mesh_translate","mesh_extrude" then cmd["delta"]=vector(raw.fetch("delta"))
        when "mesh_subdivide" then cmd["cuts"]=integer(raw.fetch("cuts",1),1,4)
        when "mesh_inset","mesh_bevel","mesh_merge" then cmd["amount"]=number(raw.fetch("amount"),0.000001,10000);cmd["segments"]=integer(raw.fetch("segments",2),1,8) if kind=="mesh_bevel"
        when "mesh_smooth" then cmd.merge!("amount"=>number(raw.fetch("amount",0.5),0,1),"iterations"=>integer(raw.fetch("iterations",1),1,10))
        when "sculpt" then cmd.merge!("center"=>vector(raw.fetch("center")),"delta"=>vector(raw.fetch("delta")),"radius"=>number(raw.fetch("radius"),0.001,10000))
        when "modifier"
          allowed={"SUBSURF"=>{"levels"=>[0,3],"render_levels"=>[0,3]},"MIRROR"=>{"use_clip"=>[0,1]},"SOLIDIFY"=>{"thickness"=>[-100,100]},"BEVEL"=>{"width"=>[0,100],"segments"=>[1,8]},"DECIMATE"=>{"ratio"=>[0.001,1]}}
          spec=allowed[raw["type"]] || raise(ArgumentError,"Unsupported modifier")
          properties=raw.fetch("properties",{}).to_h
          raise ArgumentError,"Unknown modifier property" unless (properties.keys-spec.keys).empty?
          cmd.merge!("type"=>raw["type"],"name"=>name(raw.fetch("name")),"properties"=>properties.to_h { |k,v| [k,k=="use_clip" ? ActiveModel::Type::Boolean.new.cast(v) : %w[levels render_levels segments].include?(k) ? integer(v,*spec[k]) : number(v,*spec[k])] })
        when "bone_pose"
          cmd["bone"]=name(raw.fetch("bone"));%w[location rotation scale].each { |k| cmd[k]=vector(raw.fetch(k,k=="scale" ? [1,1,1] : [0,0,0])) }
        when "bone_add"
          cmd.merge!("name"=>name(raw.fetch("name")),"head"=>vector(raw.fetch("head")),"tail"=>vector(raw.fetch("tail")))
          raise ArgumentError,"Bone head and tail must differ" if cmd["head"]==cmd["tail"]
          cmd["parent"]=name(raw["parent"]) if raw["parent"].present?
        when "weight" then cmd.merge!("group"=>name(raw.fetch("group")),"weight"=>number(raw.fetch("weight"),0,1))
        when "shape_key" then cmd.merge!("name"=>name(raw.fetch("name")),"value"=>number(raw.fetch("value"),-10,10))
        when "keyframe"
          %w[location rotation scale].each { |k| cmd[k]=vector(raw[k]) if raw.key?(k) }
          raise ArgumentError,"Choose an animated transform" if cmd.length==1
          cmd["frame"]=integer(raw.fetch("frame"),1,216000)
        end
        if kind=="sculpt" && raw["path"]
          raise ArgumentError,"Use at most 31 additional brush samples" unless raw["path"].is_a?(Array) && raw["path"].length<=31
          cmd["path"]=raw["path"].map { |point| vector(point) }
        end
        cmd["frame"]=integer(raw["frame"],1,216000) if raw.key?("frame") && %w[bone_pose shape_key].include?(kind)
        if kind.start_with?("node_")
          scope=raw.fetch("scope");raise ArgumentError,"Choose a material, geometry or compositor graph" unless NODES.key?(scope)
          cmd["scope"]=scope
          cmd["slot"]=integer(raw.fetch("slot",0),0,63) if scope=="material"
          cmd["modifier"]=name(raw.fetch("modifier","Studio Geometry")) if scope=="geometry"
          cmd["name"]=name(raw.fetch("name")) unless kind=="node_link"
          case kind
          when "node_add"
            raise ArgumentError,"Unsupported node type" unless NODES[scope].include?(raw["type"])
            cmd.merge!("type"=>raw["type"],"location"=>vector(raw.fetch("location",[0,0]),2))
          when "node_link" then cmd.merge!("from"=>name(raw.fetch("from")),"to"=>name(raw.fetch("to")),"input"=>integer(raw.fetch("input"),0,255),"output"=>integer(raw.fetch("output"),0,255))
          when "node_value"
            value=raw.fetch("value");value=value.is_a?(Array) ? vector(value,value.length.clamp(1,4)) : value==true || value==false ? value : number(value)
            cmd.merge!("input"=>integer(raw.fetch("input"),0,255),"value"=>value)
          end
        end
        cmd
      end
    end
  end
end
