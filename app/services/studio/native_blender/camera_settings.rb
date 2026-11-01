# frozen_string_literal: true
module Studio
  module NativeBlender
    class CameraSettings
      DEFAULTS={"camera_type"=>"PERSP","fov_degrees"=>39.5978,"fisheye_fov"=>180.0,"fisheye_lens"=>10.5,"lens"=>50.0,"lens_unit"=>"MILLIMETERS","sensor_fit"=>"AUTO","sensor_width"=>36.0,"sensor_height"=>24.0,"shift_x"=>0.0,"shift_y"=>0.0,
        "clip_start"=>0.1,"clip_end"=>1000.0,"ortho_scale"=>6.0,"dof_enabled"=>false,"focus_distance"=>10.0,"aperture_fstop"=>2.8,"aperture_blades"=>0,"aperture_rotation"=>0.0,"aperture_ratio"=>1.0,"panorama_type"=>"EQUIRECTANGULAR","focus_object_name"=>"","latitude_min"=>-90.0,"latitude_max"=>90.0,"longitude_min"=>-180.0,"longitude_max"=>180.0,
        "fisheye_polynomial_k0"=>-0.0000117351437,"fisheye_polynomial_k1"=>-0.0199887361,"fisheye_polynomial_k2"=>-0.00000335253,"fisheye_polynomial_k3"=>0.00000309928,"fisheye_polynomial_k4"=>-0.0000000260646,
        "stereo_convergence_mode"=>"OFFAXIS","stereo_pivot"=>"LEFT","stereo_interocular_distance"=>0.065,"stereo_convergence_distance"=>1.95}.freeze
      RANGES={"fov_degrees"=>[1,179],"fisheye_fov"=>[0.1,360],"fisheye_lens"=>[0.01,1000],"lens"=>[1,1200],"sensor_width"=>[1,100],"sensor_height"=>[1,100],"shift_x"=>[-10,10],"shift_y"=>[-10,10],"clip_start"=>[0.001,10000],"clip_end"=>[0.002,1000000],"ortho_scale"=>[0.001,100000],"focus_distance"=>[0.001,100000],"aperture_fstop"=>[0.1,128],"aperture_rotation"=>[-360,360],"aperture_ratio"=>[0.01,100],"latitude_min"=>[-90,90],"latitude_max"=>[-90,90],"longitude_min"=>[-180,180],"longitude_max"=>[-180,180],"stereo_interocular_distance"=>[0,10],"stereo_convergence_distance"=>[0.0001,1000000]}.merge((0..4).to_h { |i| ["fisheye_polynomial_k#{i}",[-1000000,1000000]] }).freeze
      PRESETS={
        "standard_50"=>["Standard 50mm",{"lens"=>50}],"wide_24"=>["Wide 24mm",{"lens"=>24}],"portrait_85"=>["Portrait 85mm",{"lens"=>85,"dof_enabled"=>true,"focus_distance"=>5,"aperture_fstop"=>1.8}],
        "telephoto_135"=>["Telephoto 135mm",{"lens"=>135}],"orthographic"=>["Orthographic",{"camera_type"=>"ORTHO","ortho_scale"=>8}],
        "panorama_360"=>["360° equirectangular",{"camera_type"=>"PANO","panorama_type"=>"EQUIRECTANGULAR"}],"fisheye"=>["Fisheye equidistant",{"camera_type"=>"PANO","panorama_type"=>"FISHEYE_EQUIDISTANT"}]
      }.freeze
      def self.presets = PRESETS.map { |key,(name,values)| {key:key,name:name,settings:DEFAULTS.merge(values)} }
      def self.preset(key)
        DEFAULTS.merge(PRESETS.fetch(key) { raise ArgumentError,"Choose a Blender camera preset" }.last)
      end
      def self.normalize(raw,base: {})
        raw=raw.to_h.stringify_keys.slice(*DEFAULTS.keys)
        data=DEFAULTS.merge(base.to_h.slice(*DEFAULTS.keys)).merge(raw)
        {"camera_type"=>%w[PERSP ORTHO PANO],"sensor_fit"=>%w[AUTO HORIZONTAL VERTICAL],"lens_unit"=>%w[MILLIMETERS FOV],"panorama_type"=>%w[EQUIRECTANGULAR EQUIANGULAR_CUBEMAP_FACE FISHEYE_EQUIDISTANT FISHEYE_EQUISOLID FISHEYE_LENS_POLYNOMIAL MIRRORBALL],"stereo_convergence_mode"=>%w[OFFAXIS PARALLEL TOE],"stereo_pivot"=>%w[LEFT RIGHT CENTER]}.each do |key,values|
          raise ArgumentError,"Choose a supported Blender #{key.humanize.downcase}" unless values.include?(data[key])
        end
        RANGES.each do |key,(min,max)|
          value=Float(data[key]);raise ArgumentError,"Camera #{key.humanize.downcase} is outside its range" unless value.finite? && value.between?(min-0.0001,max+0.0001)
          data[key]=value.clamp(min,max)
        end
        data["aperture_blades"]=Integer(data["aperture_blades"])
        raise ArgumentError,"Use zero or 3–16 aperture blades" unless data["aperture_blades"]==0 || data["aperture_blades"].between?(3,16)
        raise ArgumentError,"Panoramic crop maximum must follow minimum" unless data["latitude_max"]>data["latitude_min"] && data["longitude_max"]>data["longitude_min"]
        data["focus_object_name"]=data["focus_object_name"].to_s.first(200)
        data["dof_enabled"]=ActiveModel::Type::Boolean.new.cast(data["dof_enabled"])
        raise ArgumentError,"Camera far clip must follow near clip" unless data["clip_end"]>data["clip_start"]
        data
      end
    end
  end
end
