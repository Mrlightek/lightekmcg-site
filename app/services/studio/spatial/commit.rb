# frozen_string_literal: true
require "digest"
module Studio
  module Spatial
    class Commit
      # The canonical database revision advances before a runtime acknowledgement.
      # Receipts are saved with the scene, so retries survive sidecar restarts.
      def self.call(access,scene_id,command)
        scene=access.scene!(scene_id)
        scene.with_lock do
          settings=scene.settings.deep_dup;receipts=Array(settings["spatial_receipts"])
          fingerprint=Digest::SHA256.hexdigest(JSON.generate(canonical(command)))
          if (receipt=receipts.find { |entry| entry["id"]==command.fetch("message_id") })
            raise ArgumentError,"Message ID reused" unless receipt["fingerprint"]==fingerprint
            return {revision:receipt["revision"]}
          end
          raise ArgumentError,"CONFLICT: scene revision changed" unless Integer(command.fetch("scene_revision"))==scene.lock_version
          payload=command.fetch("payload")
          raise ArgumentError,"Only shot edits may be saved" unless payload["mode"]=="commit" && payload["role"]!="viewer"
          object=scene.scene_objects.find(payload[command["type"]=="CAMERA_UPDATE" ? "camera_id" : "object_id"])
          definition=object.definition.deep_dup
          case command["type"]
          when "ASSET_TRANSFORM"
            definition["location"]=vector(payload.fetch("position"),3,-1_000_000,1_000_000)
            definition["scale"]=vector(payload.fetch("scale"),3,-10000,10000)
            raise ArgumentError,"Scale must not be zero" if definition["scale"].any? { |value| value.abs<0.000001 }
            definition["rotation"]=euler(vector(payload.fetch("rotation_quaternion"),4,-1,1))
          when "CAMERA_UPDATE"
            raise ArgumentError,"Choose a camera" unless object.object_type=="camera"
            if payload["activate"]
              settings.merge!("active_camera_object_id"=>object.id,"active_camera"=>definition["blender_object_name"].presence || object.name)
            end
            if payload["camera_world_matrix"]
              m=vector(payload["camera_world_matrix"],16,-1_000_000,1_000_000)
              raise ArgumentError,"Camera matrix must be affine" unless m.values_at(3,7,11).all? { |x| x.abs<1e-6 } && (m[15]-1).abs<1e-6
              # Camera matrices have unit orthogonal axes; reject scale/shear rather than losing it.
              axes=[m[0,3],m[4,3],m[8,3]]
              raise ArgumentError,"Camera axes must be orthonormal" unless axes.all? { |a| (a.sum { |v| v*v }-1).abs<1e-4 } && axes.combination(2).all? { |a,b| a.zip(b).sum { |x,y| x*y }.abs<1e-4 }
              definition.delete("look_at")
              definition["location"]=m[12,3]
              definition["rotation"]=[Math.atan2(m[6],m[10]),Math.asin([[-m[2],-1].max,1].min),Math.atan2(m[1],m[0])].map { |v| v*180/Math::PI }
            end
            if payload.key?("focal_length_mm")
              definition["lens"]=vector([payload["focal_length_mm"]],1,2,250).first
              definition["lens_unit"]="MILLIMETERS"
            end
            if payload["lens_shift"]
              definition["shift_x"],definition["shift_y"]=vector(payload["lens_shift"],2,-2,2)
            end
          else raise ArgumentError,"Unsupported persistent edit"
          end
          object.update!(definition:definition)
          revision=scene.lock_version+1
          settings["spatial_receipts"]=(receipts+[{"id"=>command["message_id"],"fingerprint"=>fingerprint,"revision"=>revision}]).last(256)
          scene.update!(settings:settings)
          {revision:scene.lock_version}
        end
      end
      def self.canonical(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [key,canonical(value[key])] }
        when Array then value.map { |entry| canonical(entry) }
        else value
        end
      end
      def self.vector(value,length,min,max)
        raise ArgumentError,"Invalid transform" unless value.is_a?(Array) && value.length==length
        value.map { |v| x=Float(v);raise ArgumentError,"Invalid transform" unless x.finite? && x.between?(min,max);x }
      end
      def self.euler(q)
        length=Math.sqrt(q.sum { |v| v*v });raise ArgumentError,"Quaternion must not be zero" if length<1e-8
        x,y,z,w=q.map { |v| v/length }
        [Math.atan2(2*(w*x+y*z),1-2*(x*x+y*y)),Math.asin([[2*(w*y-z*x),-1].max,1].min),Math.atan2(2*(w*z+x*y),1-2*(y*y+z*z))].map { |v| v*180/Math::PI }
      end
    end
  end
end
