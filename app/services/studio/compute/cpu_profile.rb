# frozen_string_literal: true
module Studio
  module Compute
    class CpuProfile
      ID="cpu_economy"
      class Busy < StandardError; end
      def self.economy?(manifest) = manifest.dig("scene","settings","compute_profile")==ID
      def self.settings(raw)
        settings=raw.deep_dup;profile=settings.fetch("compute_profile","custom")
        raise ArgumentError,"Choose CPU economy or custom render settings" unless [ID,"custom"].include?(profile)
        return settings unless profile==ID
        width=Integer(settings.fetch("resolution_x",1280));height=Integer(settings.fetch("resolution_y",720))
        raise ArgumentError,"CPU source dimensions must be 16–16384 pixels" unless width.between?(16,16384) && height.between?(16,16384)
        factor=[1.0,512.0/[width,height].max].min
        settings.merge("render_engine"=>"CYCLES","resolution_x"=>[(width*factor/2).floor*2,16].max,
          "resolution_y"=>[(height*factor/2).floor*2,16].max,"resolution_percentage"=>100,"samples"=>Integer(settings.fetch("samples",8)).clamp(1,8))
      end
      # One slot per application worker host by default. A shared local lock root
      # can coordinate its processes; this is not cross-server federation.
      def self.with_slot
        root=Pathname(ENV.fetch("STUDIO_CPU_RENDER_LOCK_ROOT",Rails.root.join("storage/studio-cpu").to_s));FileUtils.mkdir_p(root,mode:0700)
        count=Integer(ENV.fetch("STUDIO_CPU_RENDER_SLOTS","1"));raise ArgumentError,"Use 1–8 CPU render slots" unless count.between?(1,8)
        handle=nil
        count.times do |index|
          candidate=File.open(root.join("slot-#{index}.lock"),File::RDWR|File::CREAT,0600)
          if candidate.flock(File::LOCK_EX|File::LOCK_NB);handle=candidate;break;end
          candidate.close
        end
        raise Busy,"Waiting for an available CPU rendering slot" unless handle
        yield
      ensure
        handle&.close
      end
    end
  end
end
