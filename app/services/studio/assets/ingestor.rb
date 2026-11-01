require "open3"
require "timeout"
require "tmpdir"
require "fileutils"
module Studio
  module Assets
    class Ingestor
      def self.call(asset, source_path: nil, source_root: nil)
        new(asset, source_path: source_path, source_root: source_root).call
      end
      def initialize(asset, source_path: nil, source_root: nil)
        @asset, @source_path, @source_root = asset, source_path, source_root
      end
      def call
        @asset.update!(status: "processing", error_message: nil)
        with_source do |source|
          Dir.mktmpdir("lightek-asset-") do |root|
            input = @source_path || File.join(root,"source#{File.extname(@asset.file.filename.to_s)}")
            FileUtils.cp(source.path,input) unless @source_path
            if %w[blend glb].include?(@asset.kind)
              convert_model(input, root)
              @asset.proxy.attach(io: File.open(File.join(root,"asset.glb")), filename: "asset.glb", content_type: "model/gltf-binary") if File.file?(File.join(root,"asset.glb"))
              @asset.thumbnail.attach(io: File.open(File.join(root,"preview.png")), filename: "preview.png", content_type: "image/png") if File.file?(File.join(root,"preview.png"))
              @asset.native.attach(io: File.open(File.join(root,"native.blend")), filename: "#{@asset.file.filename.base}.blend", content_type: "application/x-blender") if File.file?(File.join(root,"native.blend"))
              @asset.metadata = @asset.metadata.merge(JSON.parse(File.read(File.join(root,"asset.json"))))
            else
              stdout = run!([ENV.fetch("LIGHTEK_FFPROBE","ffprobe"),"-v","error","-protocol_whitelist","file,pipe","-show_streams","-show_format","-of","json",input], timeout: 30,root:root)
              data = JSON.parse(stdout)
              streams = Array(data["streams"])
              raise ArgumentError, "Unsupported media container" if data.dig("format","format_name").to_s.match?(/hls|concat|dash/)
              stream = streams.find { |s| s["codec_type"] == (@asset.kind == "audio" ? "audio" : "video") }
              raise ArgumentError, "No compatible media stream found" unless stream
              @asset.metadata = { "duration" => data.dig("format","duration").to_f, "width" => stream["width"], "height" => stream["height"], "has_audio" => streams.any?{|s|s["codec_type"]=="audio"} }
              @asset.proxy.attach(@asset.file.blob)
              if @asset.kind != "audio"
                preview=File.join(root,"preview.png")
                run!([ENV.fetch("LIGHTEK_FFMPEG","ffmpeg"),"-v","error","-y","-protocol_whitelist","file,pipe","-i",input,"-frames:v","1","-vf","scale=480:-2",preview],root:root)
                @asset.thumbnail.attach(io:File.open(preview),filename:"preview.png",content_type:"image/png")
              end
            end
            @asset.save!
          end
        end
        @asset.update!(status: "ready")
        @asset
      rescue StandardError => error
        @asset.update!(status: "failed", error_message: error.message.to_s.first(1000))
        raise
      end
      private
      def with_source
        if @source_path
          yield Struct.new(:path).new(@source_path)
        else
          attachment=@asset.kind=="blend" && @asset.native.attached? ? @asset.native : @asset.file
          attachment.blob.open { |source| yield source }
        end
      end
      def convert_model(input, root)
        script = Rails.root.join("blender/import_asset.py").to_s
        if Rails.env.production?
          image = ENV.fetch("STUDIO_ASSET_WORKER_IMAGE")
          FileUtils.mkdir_p(File.join(root,"out"))
          # Uploaded Blender files execute in a networkless, unprivileged worker
          # with only this asset mounted, without application files or secrets.
          input_root=@source_root || File.dirname(input)
          input_relative=Pathname(input).relative_path_from(Pathname(input_root)).to_s
          Studio::MediaProcess.run!(["docker","run","--rm","--name","lightek-asset-#{SecureRandom.hex(8)}","--network","none","--read-only","--cap-drop","ALL","--security-opt","no-new-privileges","--pids-limit","128","--memory","2g","--cpus","2","--user", "#{Process.uid}:#{Process.gid}","--tmpfs","/tmp:rw,nosuid,size=512m","-v","#{input_root}:/source:ro","-v","#{script}:/input/import_asset.py:ro","-v","#{root}/out:/output:rw",image,"blender","--background","--factory-startup","--disable-autoexec", "--python-exit-code", "1","--python","/input/import_asset.py","--","/source/#{input_relative}","/output",@asset.kind], timeout:240)
          %w[asset.glb preview.png asset.json native.blend].each { |name| FileUtils.mv(File.join(root,"out",name),File.join(root,name)) if File.file?(File.join(root,"out",name)) }
        else
          command = ENV["STUDIO_BPY_PYTHON"].present? ? [ENV["STUDIO_BPY_PYTHON"],script] : [ENV.fetch("BLENDER_BIN","blender"),"--background","--factory-startup","--disable-autoexec", "--python-exit-code", "1","--python",script]
          run!(command+["--",input,root,@asset.kind],timeout:240)
        end
      rescue RuntimeError, Timeout::Error => error
        # A viewport conversion must not discard a successfully packed native
        # Blender source. Its import remains usable with an explicit warning.
        output=Rails.env.production? ? File.join(root,"out") : root
        raise unless @asset.kind=="blend" && File.file?(File.join(output,"native.blend")) && File.file?(File.join(output,"asset.json"))
        metadata=JSON.parse(File.read(File.join(output,"asset.json")))
        metadata["warnings"]=Array(metadata["warnings"])+["Native source retained; preview generation did not finish: #{error.message.to_s.first(250)}"]
        File.write(File.join(output,"asset.json"),JSON.generate(metadata))
        if output!=root
          %w[asset.glb preview.png asset.json native.blend].each { |name| FileUtils.mv(File.join(output,name),File.join(root,name)) if File.file?(File.join(output,name)) }
        end
      end

      def run!(command, timeout: 90,root:nil)
        if Rails.env.production? && root
          mapped=command.map{|argument|argument.start_with?(root) ? argument.sub(root,"/work") : argument}
          command=Studio::MediaProcess.container(mapped,root:root,image:ENV.fetch("STUDIO_MEDIA_WORKER_IMAGE"))
        end
        Studio::MediaProcess.run!(command,timeout:timeout)
      end
    end
  end
end
