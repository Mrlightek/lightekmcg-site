# frozen_string_literal: true
module Studio
  module NativeBlender
    class ObjectEdit
      def self.call(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        result=nil
        scene.with_lock do
          scene.lock_version=Integer(payload.fetch("lock_version"))
          object=scene.scene_objects.find(payload.fetch("object_id"))
          raise ArgumentError,"Choose an object from the native Blender scene" unless object.definition["native_original"] && object.definition["blender_object_name"]
          d=object.definition.deep_dup
          case payload.fetch("operation","save")
          when "duplicate"
            source=d["blender_object_name"]
            d.merge!("native_duplicate_of"=>source,"blender_object_name"=>"LightekCopy_#{SecureRandom.hex(8)}")
            d["location"]=d.fetch("location").dup;d["location"][0]+=1
            object=scene.scene_objects.create!(name:"#{object.name} copy",object_type:object.object_type,position:scene.scene_objects.maximum(:position).to_i+1,definition:d)
          when "delete"
            d["native_deleted"]=true;object.update!(definition:d)
            if object.object_type=="camera" && (scene.settings["active_camera_object_id"].to_i==object.id || scene.settings["active_camera"]==d["blender_object_name"])
              replacement=scene.scene_objects.where(object_type:"camera").where.not(id:object.id).find { |item| !item.definition["native_deleted"] }
              scene.settings=scene.settings.merge("active_camera_object_id"=>replacement&.id,"active_camera"=>replacement&.definition&.fetch("blender_object_name",nil) || replacement&.name)
            end
          when "restore"
            d["native_deleted"]=false;object.update!(definition:d)
          when "save"
            properties=payload.fetch("properties",{}).to_h
            %w[location rotation scale].each do |key|
              next unless properties.key?(key)
              values=Array(properties[key]).map { |v| Float(v) }
              raise ArgumentError,"Use three finite transform values" unless values.length==3 && values.all? { |v| v.finite? && v.abs<=1000000 }
              d[key]=values
            end
            %w[hide_render hide_viewport].each { |key| d[key]=ActiveModel::Type::Boolean.new.cast(properties[key]) if properties.key?(key) }
            if properties["material"]
              raise ArgumentError,"This object has no editable Principled material" if Array(d["materials"]).empty? || d["materials"].first["editable"]==false
              material=properties.fetch("material").slice("color","metallic","roughness")
              if material["color"]
                c=Array(material["color"]).map { |v| Float(v) }
                raise ArgumentError,"Use an RGBA color" unless c.length==4 && c.all? { |v| v.finite? && v.between?(0,1) }
                material["color"]=c
              end
              %w[metallic roughness].each do |key|
                next unless material.key?(key)
                value=Float(material[key]);raise ArgumentError,"Material value must be between zero and one" unless value.finite? && value.between?(0,1)
                material[key]=value
              end
              d["material_override"]=(d["material_override"] || {}).merge(material)
            end
            if d["native_type"]=="LIGHT"
              if properties["color"]
                values=Array(properties["color"]).map { |v| Float(v) }
                raise ArgumentError,"Use an RGB light color" unless values.length==3 && values.all? { |v| v.finite? && v.between?(0,1) }
                d["color"]=values
              end
              %w[energy size].each do |key|
                next unless properties.key?(key)
                value=Float(properties[key]);raise ArgumentError,"Use a nonnegative light value" unless value.finite? && value.between?(0,1000000)
                d[key]=value
              end
            end
            Array(properties["node_inputs"]).each do |input|
              socket=Array(d["node_inputs"]).find { |i| i["modifier"]==input["modifier"] && i["identifier"]==input["identifier"] }
              raise ArgumentError,"Choose an available Geometry Nodes input" unless socket
              value=socket["type"]=="NodeSocketBool" ? ActiveModel::Type::Boolean.new.cast(input["value"]) : Float(input["value"])
              if value.is_a?(Numeric)
                raise ArgumentError,"Geometry input is outside its range" unless value.finite? && value.between?(socket["min"],socket["max"])
                value=value.to_i if socket["type"]=="NodeSocketInt"
              end
              socket["value"]=value
            end
            object.update!(name:payload["name"].presence || object.name,definition:d)
          else raise ArgumentError,"Choose save, duplicate, delete or restore"
          end
          scene.settings=scene.settings.merge("native_revision"=>scene.settings.fetch("native_revision",0).to_i+1)
          scene.save!
          result={scene_id:scene.id,object_id:object.id,lock_version:scene.lock_version,object:{id:object.id,name:object.name,object_type:object.object_type,definition:object.definition}}
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The native scene changed. Refresh before saving."
      end
    end
  end
end
