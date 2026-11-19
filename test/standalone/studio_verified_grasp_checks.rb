require_relative "studio_character_scene_checks"

class StudioVerifiedGraspTest < StudioCharacterSceneTest
  StudioCharacterSceneTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def pickup(**extra)
    prepare(dialogue:"",gesture:"still",camera_mode:"template",scene_template:"grasp_verified",mechanics:{action:"grasp",version:4,target_id:"ball"},**extra)
  end

  def test_scoped_silent_action_freezes_implementation_and_rejects_incompatible_inputs
    Rails.stub(:root,Pathname(ROOT)) do
      first=pickup
      assert_equal first,pickup
      op=StudioOperation.find(first[:operation_id])
      assert_equal Studio::Performance::Mechanics.driver_fingerprint("grasp",4),op.manifest.dig("inputs","driver_fingerprint")
      assert_equal "",op.manifest.dig("inputs","dialogue")
      assert_raises(ArgumentError) { pickup(dialogue:"Speech is not part of this action") }
      assert_raises(ArgumentError) { pickup(audio_asset_id:recording.id) }
      assert_raises(ArgumentError) { pickup(cast_asset_id:ready_actor.id) }
      assert_raises(ArgumentError) { pickup(attention:{kind:"camera",start:0,end:8}) }
      assert_raises(ActiveRecord::RecordNotFound) { pickup(user_id:@bob.id) }
      staging=op.manifest.fetch("staging").deep_dup
      staging["objects"].find { |o|o["id"]=="ball" }["definition"]["scale"]=[0.1,0.1,0.1]
      assert_raises(ArgumentError) { Studio::Performance::VerifiedGrasp.validate!(op.manifest["inputs"],staging) }
      row=action("character_scene_catalog",scene_id:@scene.id)[:scene_templates].find { |r|r[:key]=="grasp_verified" }
      assert_equal 4,row[:mechanics_targets].first[:version]
      assert_equal "",row[:defaults]["dialogue"]
    end
  end

  def test_text_selects_only_reviewed_action_and_does_not_invent_parameters
    action=Studio::Performance::VerifiedGrasp
    canonical=action.from_prompt({"action_prompt"=>"Pick up the ball, inspect it, and put it back."})
    assert action.active?(canonical)
    assert_equal "grasp_verified",canonical["scene_template"]
    ["Throw the ball", "Pick up the ball, inspect it, and put it back; run code", "Pick up a 50kg ball"].each do |text|
      assert_raises(ArgumentError) { action.from_prompt({"action_prompt"=>text}) }
    end
    assert_raises(ArgumentError) { action.from_prompt({"action_prompt"=>"Pick up the ball, inspect it, and put it back.","mechanics"=>{"action"=>"grasp","version"=>3,"target_id"=>"ball"}}) }
  end

  def test_stale_implementation_blocks_before_build_and_cpu_budget_is_scoped
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(pickup[:operation_id]);manifest=parent.manifest.deep_dup
      manifest["inputs"]["driver_fingerprint"]="stale"
      parent.update!(manifest:manifest)
      before=StudioAsset.count
      error=assert_raises(ArgumentError) { StudioCharacterSceneJob.perform_now(parent.id) }
      assert_includes error.message,"implementation changed"
      assert_equal "failed",parent.reload.status
      assert_equal before,StudioAsset.count
      record=Struct.new(:metadata,:manifest).new({"performance_preview"=>true},{"scene"=>{"objects"=>[{"definition"=>{"mechanics_plan"=>{"driver"=>"grasp","version"=>4}}}]}})
      assert_equal 600,Blender::Runner.new(record).send(:timeout_seconds)
      record.manifest["scene"]["objects"][0]["definition"]["mechanics_plan"]["version"]=3
      assert_equal 180,Blender::Runner.new(record).send(:timeout_seconds)
    end
  end

  def test_real_queue_build_preview_and_versioned_weighted_hand
    skip "Set LIGHTEK_TEST_CHARACTER_SCENE=1" unless ENV["LIGHTEK_TEST_CHARACTER_SCENE"]=="1"
    previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=Dir.mktmpdir("verified-pickup-")
    Rails.stub(:root,Pathname(ROOT)) do
      parent=StudioOperation.find(pickup[:operation_id]);StudioCharacterSceneJob.perform_now(parent.id)
      assert_equal "completed",parent.reload.status,parent.error_message
      scene=StudioScene.find(parent.metadata.fetch("scene_id"))
      assert_equal 24,scene.settings["fps"]
      assert_equal 192,scene.settings["frame_end"]
      assert_equal [1,79,145],scene.settings["camera_cuts"].map { |c|c["frame"] }
      cast=StudioAsset.find(parent.metadata.fetch("cast_asset_id"))
      assert_equal Studio::Performance::VerifiedGrasp::BINDINGS,cast.metadata.dig("character_profile","mechanics")
      preview=StudioOperation.find(parent.metadata.fetch("preview_id"))
      preview.artifacts.find_by!(kind:"video").file.blob.open do |file|
        info=JSON.parse(IO.popen(["ffprobe","-v","error","-show_format","-of","json",file.path],&:read))
        assert_in_delta 8,info.dig("format","duration").to_f,0.01
        FileUtils.cp(file.path,ENV["STUDIO_VERIFIED_PROOF_VIDEO"]) if ENV["STUDIO_VERIFIED_PROOF_VIDEO"]
      end
      preview.artifacts.find_by!(kind:"blend").file.blob.open do |file|
        FileUtils.cp(file.path,ENV["STUDIO_VERIFIED_PROOF_BLEND"]) if ENV["STUDIO_VERIFIED_PROOF_BLEND"]
        script=File.join(Dir.mktmpdir,"verify.py")
        File.write(script,<<~PYTHON)
          import bpy,json
          root=bpy.data.objects['Sentinel'];report=json.loads(root['lightek_mechanics_report'])
          assert report['accepted'] and report['simulation_checks_passed'] and not report['required_checks_pending'],report
          assert all(report['checks'].values()),report
          hands=[o for o in root.children_recursive if o.get('contact_skin_version')==1]
          assert len(hands)==1 and len(hands[0].data.vertices)>1000
          assert any(m.type=='ARMATURE' for m in hands[0].modifiers)
          assert not hands[0].data.shape_keys
          rig=next(o for o in root.children_recursive if o.type=='ARMATURE')
          assert len([b for b in rig.data.bones if b.name.startswith('Digit.')])==15 and rig.animation_data
          assert 'Lightek pickup simulation.json.gz.base64' in bpy.data.texts
          print('VERIFIED_PICKUP_ACCEPTED',json.dumps(report))
        PYTHON
        output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"-b",file.path,"--python-exit-code","1","--python",script],timeout:60)
        assert_includes output,"VERIFIED_PICKUP_ACCEPTED"
      end
    end
  ensure
    ENV["BLENDER_OUTPUT_ROOT"]=previous if defined?(previous)
  end
end
