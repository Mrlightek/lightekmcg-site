# frozen_string_literal: true
require "digest"
module Studio
  module NativeBlender
    class Appearance
      LOOK={"exposure"=>[-5,5,0],"gamma"=>[0.1,3,1],"saturation"=>[0,2,1],"contrast"=>[-100,100,0],"blur"=>[0,20,0],"glow"=>[0,1,0],"glow_threshold"=>[0,10,1]}.freeze
      SURFACE={"metallic"=>[0,1,0],"roughness"=>[0,1,0.5],"transmission"=>[0,1,0],"ior"=>[1,3,1.5],"opacity"=>[0,1,1],"emission_strength"=>[0,20,0]}.freeze
      def self.scene(access,id)
        scene=access.scene!(id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id.to_i==access.site_id.to_i
        scene
      end
      def self.defaults = LOOK.transform_values{|range|range.last}
      def self.number(value,range)
        n=Float(value)
        raise ArgumentError,"Appearance value is outside its supported range" unless n.finite? && n.between?(range[0],range[1])
        n
      end
      def self.surface(raw)
        raise ArgumentError,"Unsupported material input" unless (raw.keys-%w[color emission_color]-SURFACE.keys).empty?
        raw.to_h.each_with_object({}) do |(key,value),result|
          if %w[color emission_color].include?(key)
            raise ArgumentError,"Use an RGBA color" unless value.is_a?(Array) && value.length==4
            result[key]=value.map{|part|number(part,[0,1])}
          else
            result[key]=number(value,SURFACE.fetch(key))
          end
        end
      end
      def self.targets(access,scene)
        scene.scene_objects.flat_map do |object|
          d=object.definition
          next [] if d["native_deleted"]
          materials=if %w[cube sphere cylinder plane].include?(object.object_type)
            value=d.dig("material","color")
            rgba=value.is_a?(Array) ? (value+[0.55,0.58,0.65,1]).first(4) : [0.55,0.58,0.65,1]
            [["",[{"slot"=>0,"name"=>object.name,"editable"=>true,"color"=>rgba,"emission_color"=>[1,1,1,1]}.merge(SURFACE.transform_values{|r|r.last}).merge("opacity"=>rgba[3]).merge(d.fetch("material",{}).slice("metallic","roughness","transmission"))]]]
          elsif d["native_original"]
            [["",Array(d["materials"])]]
          elsif d["character_profile"]
            asset=StudioAsset.for_actor(access).where(site_id:access.site_id).find(d.fetch("asset_id"))
            profile=d["character_profile"]
            raise ArgumentError,"This character source changed. Register its updated Cast source." unless asset.native.attached? && asset.native.blob.id==profile["source_blob_id"]
            source=Array(asset.metadata["scenes"]).find{|s|s["name"]==profile["source_scene"]}
            Array(source&.fetch("objects",[])).filter_map{|child|[child["name"],Array(child.dig("definition","materials"))] if profile["objects"].include?(child["name"])}
          else []
          end
          materials.flat_map do |target,slots|
            slots.filter_map do |material|
              next if material["editable"]==false
              slot=material.fetch("slot",0)
              base=SURFACE.transform_values{|range|range.last}.merge("color"=>[0.55,0.58,0.65,1],"emission_color"=>[1,1,1,1]).merge(material.slice("color","emission_color",*SURFACE.keys))
              base.merge!(d["material_override"] || {}) if target.empty? && slot==Array(d["materials"]).first&.fetch("slot",0)
              override=Array(d["surface_overrides"]).find{|item|item["target"]==target && item["slot"]==slot}
              {object_id:object.id,target:target,slot:slot,name:[object.name,target.presence,material["name"]].compact.join(" / "),values:base.merge(override&.fetch("values",{}) || {}),overridden:!!override,linked_fields:Array(material["linked_fields"]),fields:target.empty? && %w[cube sphere cylinder plane].include?(object.object_type) ? ["color","emission_color",*SURFACE.keys] : (material.keys & ["color","emission_color",*SURFACE.keys])}
            end
          end
        end
      end
      def self.status(access:,payload:)
        record=scene(access,payload.fetch("scene_id"))
        {scene_id:record.id,lock_version:record.lock_version,native_revision:record.settings.fetch("native_revision",0),look:defaults.merge(record.settings.fetch("look",{})),targets:targets(access,record)}
      end
      def self.save(access:,payload:,material:false)
        record=scene(access,payload.fetch("scene_id"));key=payload.fetch("request_key").to_s
        raise ArgumentError,"An appearance request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        fingerprint=Digest::SHA256.hexdigest([material,payload.except("request_key","lock_version","user_id","site_id","origin")].to_json)
        result=nil
        record.with_lock do
          receipts=record.settings.fetch("look_receipts",{})
          if receipts[key]
            raise ArgumentError,"This request key belongs to a different appearance edit" unless receipts[key]["fingerprint"]==fingerprint
            return receipts[key]
          end
          reset=payload.fetch("operation","apply")=="reset"
          raise ArgumentError,"Choose apply or reset" unless %w[apply reset].include?(payload.fetch("operation","apply"))
          record.lock_version=Integer(payload.fetch("lock_version"))
          settings=record.settings.deep_dup
          if material
            target=targets(access,record).find{|item|item[:object_id]==Integer(payload.fetch("object_id")) && item[:target]==payload.fetch("target","") && item[:slot]==Integer(payload.fetch("slot",0))}
            raise ArgumentError,"Choose an editable material from this scene" unless target
            object=record.scene_objects.find(target[:object_id]);overrides=Array(object.definition["surface_overrides"]).deep_dup
            old=overrides.find{|item|item["target"]==target[:target] && item["slot"]==target[:slot]}
            overrides.delete(old)
            unless reset
              values=(old&.fetch("values",{}) || {}).merge(surface(payload.fetch("values").to_h))
              overrides<<{"target"=>target[:target],"slot"=>target[:slot],"values"=>values} unless values.empty?
            end
            raise ArgumentError,"Use at most 128 material overrides per character" if overrides.length>128
            object.update!(definition:object.definition.merge("surface_overrides"=>overrides))
          else
            raw=payload.fetch("look",{}).to_h
            raise ArgumentError,"Unsupported scene look setting" unless (raw.keys-LOOK.keys).empty?
            settings["look"]=reset ? {} : defaults.merge(settings.fetch("look",{})).merge(raw.to_h{|field,value|[field,number(value,LOOK.fetch(field))]})
          end
          settings["native_revision"]=settings.fetch("native_revision",0).to_i+1
          result={"scene_id"=>record.id,"lock_version"=>record.lock_version+1,"fingerprint"=>fingerprint}
          settings["look_receipts"]=receipts.to_a.last(99).to_h.merge(key=>result)
          record.update!(settings:settings)
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Reload appearance settings before saving."
      end
    end
  end
end
