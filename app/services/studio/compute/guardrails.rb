# frozen_string_literal: true

module Studio
  module Compute
    module Guardrails
      class Limit < ArgumentError
        attr_reader :suggestion
        def initialize(message, suggestion = {})
          @suggestion = suggestion
          super(message)
        end
      end

      GIB = 1024**3
      WAN_RECIPES = %w[wan22_video wan22_image_video].freeze
      GENESIS = {
        "economy" => {image_edge:512, video_width:512, video_height:288, min_vram:8*GIB, free_vram:4*GIB},
        "quality" => {image_edge:768, video_width:1280, video_height:704, min_vram:16*GIB, free_vram:10*GIB}
      }.freeze
      GENERATION_INPUTS = %w[scene_id recipe prompt genesis_worker_id input_asset_id driver_asset_id aspect_ratio seed steps quality_profile].freeze
      WAN_FRAMES = 121
      SAMPLE_STEPS = 60
      CPU_EDGE = 512
      CPU_SAMPLES = 8
      CPU_FRAMES = 2400
      CPU_MEMORY = "1g"
      CPU_TIMEOUT = 7200
      LEASE_SECONDS = 90
      EDIT_EDGE = 4096
      EDIT_SECONDS = 600
      EDIT_CLIPS = 64
      MEDIA_MEMORY = "2g"
      EDIT_TIMEOUT = 900
      SPEECH_SECONDS = 30
      SPEECH_TIMEOUT = 180
      PERFORMANCE_MEMORY = "12g"
      PERFORMANCE_SECONDS = 15
      PERFORMANCE_TIMEOUT = 1800

      module_function

      # CPU/memory allocation and arbitrary graphs are an operator contract,
      # never inputs an inferred or typed Studio command can override.
      def preflight!(capability,payload)
        return unless %w[studio.workspace.ai.generate studio.workspace.render.quote studio.workspace.timeline.save studio.workspace.timeline.quote studio.workspace.performance.analyze studio.workspace.performance.preview].include?(capability)
        overrides=%w[graph workflow memory memory_bytes vram_bytes width height frames batch_size fps samples resolution_x resolution_y render_engine]
        if (payload.keys & overrides).any?
          raise Limit.new("Use the Studio presets. I can run this with Economy settings within the worker limits.",capability=="studio.workspace.ai.generate" ? {"quality_profile"=>"economy"} : {})
        end
        case capability
        when "studio.workspace.ai.generate"
          profile=payload.fetch("quality_profile","auto")
          unless %w[auto economy quality].include?(profile)
            raise Limit.new("Choose Auto, Economy or Quality. Economy uses up to 512 pixels.",{"quality_profile"=>"economy"})
          end
          if payload.key?("steps") && !payload["steps"].to_s.match?(/\A(?:[1-9]|[1-5][0-9]|60)\z/)
            raise Limit.new("Use #{SAMPLE_STEPS} sampling steps or fewer. Start with 20 and Economy if the worker is short on memory.",{"steps"=>20,"quality_profile"=>"economy"})
          end
        when "studio.workspace.performance.analyze"
          if payload.key?("source_out")
            first=Float(payload.fetch("source_in",0),exception:false)
            last=Float(payload["source_out"],exception:false)
            unless first&.finite? && last&.finite? && first>=0 && (last-first).between?(0.1,SPEECH_SECONDS)
              raise Limit.new("Choose a dialogue segment between a tenth of a second and #{SPEECH_SECONDS} seconds.")
            end
          end
        when "studio.workspace.timeline.save"
          timeline=payload["timeline"]
          return unless timeline.is_a?(Hash)
          if %w[width height].any? { |key| timeline.key?(key) && (!timeline[key].to_s.match?(/\A[0-9]{2,4}\z/) || timeline[key].to_i>EDIT_EDGE) } ||
              Array(timeline["clips"]).size>EDIT_CLIPS || timeline["duration"].to_s.to_f>EDIT_SECONDS
            raise Limit.new("Keep the export at #{EDIT_EDGE} pixels per side or less, with up to #{EDIT_CLIPS} clips. Try 1920×1080 or split the edit into sections under ten minutes.")
          end
        end
      end

      def genesis_profile!(recipe, device, requested="auto")
        return "economy" if recipe=="image" && device&.fetch(:type,nil)=="cpu" && requested!="quality"
        total,free=device.to_h.values_at(:vram_total,:vram_free)
        valid=->(name) { device&.fetch(:type,nil)=="cuda" && total.to_i>=GENESIS.fetch(name)[:min_vram] && free.to_i>=GENESIS.fetch(name)[:free_vram] }
        return "quality" if requested!="economy" && valid.call("quality")
        return "economy" if requested!="quality" && valid.call("economy")
        if requested=="quality" && (valid.call("economy") || (recipe=="image" && device&.fetch(:type,nil)=="cpu"))
          raise Limit.new("Quality won’t fit on this worker. Try Economy at up to 512 pixels.",{"quality_profile"=>"economy"})
        end
        if WAN_RECIPES.include?(recipe)
          raise Limit.new("Wan needs a CUDA worker with at least 8 GiB total and 4 GiB free VRAM for Economy. Free up GPU memory or choose another CUDA worker.")
        end
        raise Limit.new("Image generation needs a healthy CPU or CUDA worker. For CUDA, free at least 4 GiB of VRAM before trying Economy.")
      end

      def genesis_graph!(graph,recipe,profile,prepare:false)
        limits=GENESIS.fetch(profile)
        wan=WAN_RECIPES.include?(recipe)
        nodes=graph.values.select { |node| node["class_type"]==(wan ? "Wan22ImageToVideoLatent" : "EmptyLatentImage") }
        raise Limit.new("This workflow has no supported image or video dimensions. Ask an operator to check the installed recipe.") if nodes.empty?
        nodes.each do |node|
          inputs=node.fetch("inputs")
          width,height=inputs.values_at("width","height")
          frames=wan ? inputs["length"] : 1
          unless [width,height,frames].all? { |value| value.is_a?(Integer) && value.positive? } && inputs.fetch("batch_size",1)==1 && frames.between?(1,WAN_FRAMES)
            raise Limit.new("Use one clip or image at a time. A Wan clip can contain up to #{WAN_FRAMES} frames.")
          end
          max_width=wan ? limits[:video_width] : limits[:image_edge]
          max_height=wan ? limits[:video_height] : limits[:image_edge]
          if prepare
            factor=[1.0,max_width.to_f/width,max_height.to_f/height].min
            if factor<1
              multiple=wan ? 16 : 8
              inputs["width"]=[(width*factor/multiple).floor*multiple,multiple].max
              inputs["height"]=[(height*factor/multiple).floor*multiple,multiple].max
            end
          elsif width>max_width || height>max_height
            raise Limit.new("The saved job exceeds this worker’s checked resolution. Start a new Economy job.",{"quality_profile"=>"economy"})
          end
        end
        if graph.values.any? { |node| node["class_type"]=="KSampler" && !node.dig("inputs","steps").to_s.match?(/\A(?:[1-9]|[1-5][0-9]|60)\z/) }
          raise Limit.new("This recipe exceeds the sampling budget. Try 20 steps.",{"steps"=>20})
        end
      end

      def economy_manifest!(manifest)
        return unless CpuProfile.economy?(manifest)
        settings=manifest.fetch("scene").fetch("settings")
        unless settings.values_at("resolution_x","resolution_y").all? { |edge| edge.is_a?(Integer) && edge.between?(16,CPU_EDGE) } &&
            settings["samples"].is_a?(Integer) && settings["samples"].between?(1,CPU_SAMPLES) && settings["resolution_percentage"]==100 && settings["render_engine"]=="CYCLES"
          raise Limit.new("Use CPU Economy at up to #{CPU_EDGE} pixels and #{CPU_SAMPLES} samples. Save those settings and quote the render again.")
        end
        return unless manifest.dig("outputs","animation")
        first,last=settings.values_at("frame_start","frame_end")
        unless first.is_a?(Integer) && last.is_a?(Integer) && first.positive? && (last-first+1).between?(1,CPU_FRAMES)
          raise Limit.new("Split this CPU render into shots of #{CPU_FRAMES} frames or fewer, then quote each shot.")
        end
      end
    end
  end
end
