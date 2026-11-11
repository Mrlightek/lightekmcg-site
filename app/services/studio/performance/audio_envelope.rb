# frozen_string_literal: true
require "tmpdir"
require "fileutils"
module Studio
  module Performance
    class AudioEnvelope
      # Volume-following animation, deliberately not described as phoneme alignment.
      def self.call(asset, first:, duration:)
        asset.file.blob.open do |source|
          Dir.mktmpdir("lightek-voice-") do |root|
            input=File.join(root,"voice#{File.extname(asset.file.filename.to_s)}")
            FileUtils.cp(source.path,input)
            command=[ENV.fetch("LIGHTEK_FFMPEG","ffmpeg"),"-v","error","-protocol_whitelist","file,pipe","-ss",first.to_s,"-i",input,"-t",duration.to_s,"-vn","-ac","1","-ar","8000","-f","s16le","-"]
            if Rails.env.production?
              command=command.map{|value|value.gsub(root,"/work")}
              command=Studio::MediaProcess.container(command,root:root,image:Studio::NativeBlender::Runtime.image(:media))
            end
            samples=Studio::MediaProcess.run!(command,timeout:45).b.unpack("s<*")
            raise ArgumentError,"No audio samples were decoded" if samples.empty?
            energy=samples.each_slice(320).map{|window|Math.sqrt(window.sum{|v|v.to_f*v}/window.length)/32768}
            peak=[energy.max,0.02].max
            energy.each_with_index.map{|value,i|{"time"=>i*0.04,"value"=>value<0.007 ? 0.0 : [value/peak,1].min.round(4)}}
          end
        end
      end
    end
  end
end
