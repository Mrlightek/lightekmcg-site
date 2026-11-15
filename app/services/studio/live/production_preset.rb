# frozen_string_literal: true
module Studio
  module Live
    class ProductionPreset
      ASSETS={"stage_asset_id"=>%w[blend glb],"visual_asset_id"=>%w[image video],"overlay_asset_id"=>%w[image],"audio_asset_id"=>%w[audio]}.freeze
      def initialize(user:,site:)
        ::Gatekeeper::StudioLivePolicy.authorize!(user:user)
        @site=site
        @access=Studio::PwaAccess.new("user_id"=>user.id,"site_id"=>site.id)
      end
      def scene!(id)
        StudioScene.where(studio_project_id:@access.projects.where(site_id:@site.id).select(:id)).find(id)
      end
      def read(id)
        scene=scene!(id)
        preset=scene.settings["live_preset"]
        preset=normalize(preset) if preset
        result(scene,preset)
      end
      def save(id,preset:,lock_version:)
        scene=scene!(id)
        normalized=normalize(preset)
        scene.with_lock do
          if scene.settings.dig("live_preset","version").to_i>normalized["version"]
            raise ArgumentError,"This setup includes newer production controls. Reload the updated Live Studio before saving."
          end
          scene.lock_version=Integer(lock_version.to_s,10)
          scene.update!(settings:scene.settings.merge("live_preset"=>normalized))
        end
        result(scene,normalized)
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"This production changed. Reload its saved live setup before saving again."
      end
      def normalize(raw)
        raise ArgumentError,"Live setup must be an object" unless raw.is_a?(Hash)
        data=raw.deep_stringify_keys
        raise ArgumentError,"Unsupported live setup fields" unless (data.keys-(%w[version layout loop volume camera subject presentation overlay]+ASSETS.keys)).empty?
        version=data.fetch("version",1)
        raise ArgumentError,"Unsupported live setup version" unless [1,2,3].include?(version)
        layout=data.fetch("layout","camera")
        raise ArgumentError,"Choose a supported live layout" unless %w[camera screen combined library stage session].include?(layout)
        result={"version"=>version,"layout"=>layout,"loop"=>boolean(data.fetch("loop",false)),"volume"=>number(data.fetch("volume",0.25),0,1),"camera"=>data.fetch("camera","").to_s}
        raise ArgumentError,"Choose an imported camera index" unless result["camera"].empty? || /\A\d{1,3}\z/.match?(result["camera"])
        ASSETS.each do |key,kinds|
          next if data[key].blank?
          raise ArgumentError,"Choose an asset ID" unless /\A[1-9]\d*\z/.match?(data[key].to_s)
          id=Integer(data[key]);asset=asset_scope.find(id)
          raise ArgumentError,"Choose a ready #{key.delete_suffix('_asset_id')} asset with a prepared proxy" unless kinds.include?(asset.kind) && asset.status=="ready" && asset.proxy.attached?
          result[key]=asset.id
        end
        raise ArgumentError,"Choose a prepared stage for this layout" if layout=="stage" && !result["stage_asset_id"]
        raise ArgumentError,"Choose program media for this layout" if layout=="library" && !result["visual_asset_id"]
        subject=data.fetch("subject",{})
        raise ArgumentError,"Unsupported subject controls" unless subject.is_a?(Hash) && (subject.keys-%w[enabled key color threshold x depth z height source]).empty?
        color=subject.fetch("color","#00ff00")
        raise ArgumentError,"Choose a key color" unless /\A#[0-9a-fA-F]{6}\z/.match?(color.to_s)
        source=subject.fetch("source","camera")
        raise ArgumentError,"Choose camera or session as stage subject" unless %w[camera session].include?(source)
        result["subject"]={"enabled"=>boolean(subject.fetch("enabled",true)),"key"=>boolean(subject.fetch("key",true)),"color"=>color,"source"=>source,
          "threshold"=>number(subject.fetch("threshold",0.4),0.05,1),"x"=>number(subject.fetch("x",0),-100,100),"depth"=>number(subject.fetch("depth",0),-100,100),"z"=>number(subject.fetch("z",1.5),-100,100),"height"=>number(subject.fetch("height",3),0.1,100)}
        if data.key?("presentation") || version>=2
          raise ArgumentError,"Show presentation requires live setup version 2" if version<2
          values=data.fetch("presentation",{})
          keys=%w[layout title subtitle brand ticker background accent]
          raise ArgumentError,"Show styling must contain only portable presentation fields" unless values.is_a?(Hash) && (values.keys-keys).empty?
          result["presentation"]=LightekSessions::Presentation.normalize!(values).slice(*keys)
        end
        if data.key?("overlay") || version==3
          raise ArgumentError,"Graphic placement requires live setup version 3" if version<3
          values=data.fetch("overlay",{})
          raise ArgumentError,"Unsupported graphic placement fields" unless values.is_a?(Hash) && (values.keys-%w[enabled x y width height opacity fit]).empty?
          fit=values.fetch("fit","stretch")
          raise ArgumentError,"Choose stretch or contain for graphic placement" unless %w[stretch contain].include?(fit)
          result["overlay"]={"enabled"=>boolean(values.fetch("enabled",true)),"fit"=>fit,
            "x"=>number(values.fetch("x",0),-1280,1280),"y"=>number(values.fetch("y",0),-720,720),
            "width"=>number(values.fetch("width",1280),1,1280),"height"=>number(values.fetch("height",720),1,720),"opacity"=>number(values.fetch("opacity",1),0,1)}
        end
        result
      end
      private
      def asset_scope = StudioAsset.for_actor(@access).where(site_id:@site.id)
      def boolean(value)
        raise ArgumentError,"Live switches must be true or false" unless [true,false].include?(value)
        value
      end
      def number(value,min,max)
        value=Float(value)
        raise ArgumentError,"Live value must be between #{min} and #{max}" unless value.finite? && value.between?(min,max)
        value
      rescue TypeError
        raise ArgumentError,"Choose a numeric live value"
      end
      def result(scene,preset)
        ids=preset ? ASSETS.keys.filter_map{|key|preset[key]} : []
        assets=asset_scope.where(id:ids).map{|asset|{id:asset.id,name:asset.name,kind:asset.kind,url:"/dashboard/studio-broadcasting/assets/#{asset.id}/proxy?site_id=#{@site.id}"}}
        {scene_id:scene.id,name:scene.name,lock_version:scene.lock_version,preset:preset,assets:assets}
      end
    end
  end
end
