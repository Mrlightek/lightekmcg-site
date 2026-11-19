# frozen_string_literal: true

module NevaehOs
  module SpecialistContext
    TOPICS = {
      "performed"=>["Performed character short","docs/studio/performed-short.md",/performed short|illustrated performer|character scene|two.character dialogue|guided acting|character entrance|pointing action|performance sequence|sequence cut/i],
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
        "Choose Performed Short in Studio Create. Select a scene setup or start an editable production/saved show, then open one of its scenes. Current scene setups preserve sets and lights; choose template cameras or frontal character coverage, and a starter action. Build a simple illustrated performer or reuse registered Cast, enter a short line for a stock voice or choose a ready 0.2–2.8 second recording. It creates a separate editable three-second scene with phoneme mouth cues, an available arm gesture and a wide-to-close cut. Requires Blender, FFmpeg, eSpeak-ng for synthesis and pinned Rhubarb speech analysis; no Genesis connection is needed. Choose Two-character dialogue for exactly two Cast identities and two to four ordered turns (speaker indices 0/1), each with a stock voice or owned recording. Both characters must speak; measured total duration including gaps must fit eight seconds. This mode adds silent bound listener reactions and alternating close cameras, retaining one identity across repeated takes. Arrange performances into a sequence accepts 2–12 completed current performances from this project, ordered and trimmed within a 30-second review cut. Same-named characters must reuse saved Cast identities. Review previews remain private; final sequence export requires current full source exports, then imports them into an editable Timeline and reuses existing checkout. Full sequence source bytes are frozen and a failed paid sequence export can reuse its payment. Guided acting accepts emotion (neutral/friendly/curious/surprised), body_action (still/point_left/point_right), entrance (none/from_left/from_right), at top level for a study or on each dialogue character. New illustrated sources include point/step Actions; saved Cast must supply its own registered source motion and required face bindings. Entrances reserve time before speech and use native NLA plus root keys at 12 fps. A study may extend to four seconds; dialogue still caps the complete scene at eight seconds. Prop interaction accepts optional contact {target_id,face,hand,start,reach,hold,release} at study top level or on each dialogue character; IDs come from scene contact_targets. Choose Control-panel interaction for an activation button. Only static cubes and registered two-bone reach_bindings are supported. Analytic arm posing bakes editable keys and measures held palm/wrist error within 2 mm; unreachable targets and collisions fail. No added body action or same-hand wave; start after any entrance (at least 1 second). Timing snaps to 12 fps and must fit eight seconds. This is bounded contact posing, not arbitrary grasping or rigid-body physics. New coordinated single-character bench mechanics accept mechanics {action: bench, version: 2, target_id: seat}; saved bench version 1 stays available. Direction-aware actions need registered front/side view bindings as well as illustrated_biped physical mechanics v1. Carry accepts mechanics {action: carry, version: 1, target_id: parcel} in the Pick up, carry and put down setup; speech starts at 2.3 s. A rigid left-palm attachment carries the calibrated parcel between its two tables, with measured support/release and environment collision checks. This carry v1 is not articulated finger grasping. For a separate physical hand study choose Physical finger grasp, scene_template grasp, camera_mode template and mechanics {action: grasp, version: 2, target_id: ball}. It runs pinned CPU MuJoCo 3.3.7 with 15 articulated finger links, force-limited motors, SI-unit mass, gravity and friction; the sphere is free, never parented/welded to the hand. New v2 studies stand beside and face the sphere, with forward-plane reach checks and stylized downward head/pupil attention; v1 remains frozen for earlier takes. It approaches, closes, lifts, lowers, opens and withdraws in eight seconds; speech starts at 3 s. The frozen adult_grasp_v1 profile uses a 0.2 kg, 0.045 m sphere and 0.35 N m finger torque. Profile/driver changes require a new version. Body reach remains anatomically bounded IK, with planted feet; only hand/load contacts are dynamically solved. Whole-body balance, arbitrary objects, physical-grip walking and multi-character contact are not implemented. For a directed performance choose Pedestal pickup · acting beats: scene_template grasp_acting, camera_mode template, mechanics {action: grasp, version: 3, target_id: ball}. Gaze establishes by 0.17 s before reach at 0.25; close 1.25–1.83; weight check 1.83–2.25; lift to 3; living hold 3–4.5; place by 5.5; release by 6.17; clear the ball before retreat; recover posture/head through 8 s. Unequal breath intervals, a 6 mm forward commitment, 1.5 mm lateral shifts, torque-limited finger adjustments and a post-clearance blink are baked once for all cameras. V3 owns gaze timing and rejects competing attention cues. The proxy character and bounded solver do not establish indistinguishable human behavior. Keep separate entrance, gesture, body_action and contact absent/still. The study preserves prepared-scene, retry, private preview and existing quote/payment paths, with a template hand close-up. Media runtime must include the pinned CPU physics venv; unavailable physics fails clearly without an attachment fallback. Attention accepts {kind: camera|object|partner, start, end, target_id?} on a study or each dialogue character. Only object mode accepts a scoped setup target_id; partner needs dialogue; camera follows the active render camera including cuts. It requires a registered attention_binding with a calibrated eye anchor and aims the head independently of body direction, bounded to 75 degrees yaw and 25 pitch; clamped reports require a body turn. A camera target supports fourth-wall direct address. World/local surface frames exist, but walking profiles still use a horizontal floor. For the bench routine, choose the Walk, sit and stand setup and a newly built illustrated performer or Cast with illustrated_biped mechanics v1. The eight-second action owns walking, turning, sitting, lap arms and standing; dialogue starts at 3.4 seconds and must end before standing at 6.4. Separate entrance/body action/gesture/contact must be none/still/absent. The calibrated seat must retain its original dimensions/transform. Source and driver fingerprints are pinned; incompatible profiles, changed implementations or collisions fail explicitly. This is calibrated kinematic posing, not dynamic balance, arbitrary proportions or mass/force physics. Preview is private. Full export uses existing checkout. Detailed acting and action choreography remain further work."
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
