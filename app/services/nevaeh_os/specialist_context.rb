# frozen_string_literal: true

module NevaehOs
  module SpecialistContext
    TOPICS = {
      "performed"=>["Performed character short","docs/studio/performed-short.md",/performed short|illustrated performer|character scene|two.character dialogue|performance sequence|sequence cut/i],
      "workflow"=>["Lightek 2D scene and parallax","docs/studio/ai-studio.md",/\bparallax\b|2[.]?5?d scene|layered scene|native.*video/i],
      "wan"=>["Wan 2.2","docs/studio/genesis-image-to-video.md",/\bwan\b|image.to.video/i],
      "sd"=>["Stable Diffusion 1.5","docs/studio/genesis-workers.md",/stable diffusion|\bsd\s*1[.]5\b/i],
      "cpu"=>["Blender Cycles Economy","docs/studio/cpu-economy.md",/\bblender\b|\bcycles\b|cpu economy/i],
      "ffmpeg"=>["FFmpeg","docs/studio/production-suite.md",/\bffmpeg\b|export.*(?:clip|video)/i],
      "speech"=>["Rhubarb Lip Sync","docs/studio/character-lip-sync.md",/\brhubarb\b|lip.sync/i],
      "performance"=>["MuseTalk, LivePortrait and FaceFusion","docs/studio/ai-studio.md",/\bmusetalk\b|\bliveportrait\b|\bfacefusion\b/i]
    }.freeze

    module_function

    def topic_for(capability,payload)
      case capability
      when "studio.workspace.sequence.prepare","studio.workspace.sequence.quote","studio.workspace.character.template.use","studio.workspace.character.scene.prepare","studio.workspace.character.scene.quote" then "performed"
      when "studio.workspace.workflow.create","studio.workspace.workflow.quote","studio.workspace.workflow.plan","studio.workspace.workflow.save" then "workflow"
      when "studio.workspace.ai.generate"
        return "wan" if Studio::Compute::Guardrails::WAN_RECIPES.include?(payload["recipe"])
        payload["recipe"]=="image" ? "sd" : "performance"
      when "studio.workspace.render.quote","studio.workspace.render.resume" then "cpu"
      when "studio.workspace.timeline.quote","studio.workspace.timeline.save" then "ffmpeg"
      when "studio.workspace.performance.analyze","studio.workspace.performance.preview" then "speech"
      end
    end

    def guidance(topic)
      rules=Studio::Compute::Guardrails
      case topic
      when "performed"
        "Choose Performed Short in Studio Create. Select a scene setup or start an editable production/saved show, then open one of its scenes. Current scene setups preserve sets and lights; choose template cameras or frontal character coverage, and a starter action. Build a simple illustrated performer or reuse registered Cast, enter a short line for a stock voice or choose a ready 0.2–2.8 second recording. It creates a separate editable three-second scene with phoneme mouth cues, an available arm gesture and a wide-to-close cut. Requires Blender, FFmpeg, eSpeak-ng for synthesis and pinned Rhubarb speech analysis; no Genesis connection is needed. Choose Two-character dialogue for exactly two Cast identities and two to four ordered turns (speaker indices 0/1), each with a stock voice or owned recording. Both characters must speak; measured total duration including gaps must fit eight seconds. This mode adds silent bound listener reactions and alternating close cameras, retaining one identity across repeated takes. Arrange performances into a sequence accepts 2–12 completed current performances from this project, ordered and trimmed within a 30-second review cut. Same-named characters must reuse saved Cast identities. Review previews remain private; final sequence export requires current full source exports, then imports them into an editable Timeline and reuses existing checkout. Full sequence source bytes are frozen and a failed paid sequence export can reuse its payment. Preview is private. Full export uses existing checkout. Detailed acting and action choreography remain further work."
      when "workflow"
        "In Create, choose 2D Scene & Parallax. Try: A nighttime park with a character sitting on a bench. Lightek supplies seeded tree and bench defaults. Edit reusable image layers and nested groups; z-index controls stacking while depth controls parallax. Select a layer or group to apply Sway, Float or Drift and edit 2–12 position keyframes with 0.25–10 second durations. Append and a gentle breeze to animate park trees. Walking, rigging and speech animation are outside this 2D compositor. A private preview is at most two seconds, 640 pixels and 12 fps. Final exports use existing checkout, up to ten seconds, 24 fps and 1920×1080 pixels in area. The CPU renderer requires FFmpeg with SVG decoding and ImageMagick, without ComfyUI or Blender. An optional full-export checkbox adds an editable packed-texture Blender project after the existing checkout; private previews cannot export it. It preserves flat planes and sampled position animation, not inferred 3D geometry. This is a template compositor, not unrestricted neural generation or a rigged character animation system."
      when "wan"
        "In Create, pick Wan 2.2 and add a prompt or starting image. Auto uses the registered worker’s available VRAM. Economy caps the clip at 512×288, and Quality at 1280×704. Both cap at #{rules::WAN_FRAMES} frames. If memory is tight, start with Economy and 20 steps."
      when "sd"
        "Pick Concept Art, describe the image, and choose its aspect ratio. CPU or Economy caps the long edge at 512 pixels. Quality on a CUDA worker can reach 768 pixels."
      when "cpu"
        "Use CPU Economy for short shots. It allows up to #{rules::CPU_EDGE} pixels on the long edge, #{rules::CPU_SAMPLES} samples, and #{rules::CPU_FRAMES} frames per shot. If a paid render is interrupted, resume from its last valid checkpoint in Activity."
      when "ffmpeg"
        "Assemble your clips in Timeline & Edit, then quote the export. Keep it at #{rules::EDIT_EDGE} pixels per side or less, up to #{rules::EDIT_CLIPS} clips and ten minutes. Use Publish to prepare a vertical 9:16 copy."
      when "speech"
        "Choose the actor and add a short, clean voice recording under Character Performance. Rhubarb analyzes the audio and generates mouth cues for the rig."
      when "performance"
        "Choose MuseTalk, LivePortrait, or FaceFusion under Character Performance. Keep video and audio inputs to #{rules::PERFORMANCE_SECONDS} seconds or less. MuseTalk accepts an audio driver. LivePortrait and FaceFusion use video."
      end
    end

    def evidence(topic)
      title,path=TOPICS.fetch(topic)
      root=Rails.root.realpath
      resource=root.join(path)
      real=resource.realpath if resource.file?
      excerpt=real&.to_s&.start_with?("#{root}/") ? File.read(real,1200,encoding:"UTF-8").scrub : nil
      {title:title,path:path,excerpt:excerpt,studio_limits:guidance(topic)}.compact
    rescue Errno::ENOENT, Errno::EACCES
      {title:title,path:path,studio_limits:guidance(topic)}
    end

    def topic_in(text)
      TOPICS.to_a.reverse.find { |_key,entry| entry[2].match?(text) }&.first
    end

    def answer(text,studio_context:)
      explicit=text.to_s.match?(/\A\s*(?:how|what|which|can|why|help|explain)\b/i)
      return unless explicit
      topic=topic_in(text)
      return unless topic && (studio_context || text.match?(/\b(?:comfyui|wan|blender|cycles|ffmpeg|musetalk|rhubarb|liveportrait|facefusion|stable diffusion)\b/i))
      source=evidence(topic)
      {"text"=>source.fetch(:studio_limits),"sources"=>[source],"status"=>"grounded"}
    end
  end
end
