# frozen_string_literal: true
require_relative "native_blender_checks"
class MediaPresetTest < NativeBlenderTest
  NativeBlenderTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def preset(key, **payload)
    action("blender_preset_use",key:key,mode:"apply",scene_id:@scene.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid,**payload)
  end
  def test_all_recovered_definitions_compile_and_keep_provenance
    items=Studio::NativeBlender::MediaPresets.items
    assert_equal 129,items.length
    assert_equal items.map { |i| i["key"] }.uniq,items.map { |i| i["key"] }
    items.each do |item|
      plan=Studio::NativeBlender::MediaPresets.compile(item["key"])
      assert_kind_of Hash,plan["directives"]["definition"],item["key"]
      assert_match(/\A[0-9a-f]{64}\z/,item["source_sha256"])
    end
    plan=Studio::NativeBlender::MediaPresets.compile("streaming/prestige_cold_open")
    assert_equal 3840,plan["settings"]["resolution_x"]
    assert_equal "slow_dolly",plan.dig("directives","definition","body","shots","camera")
    assert plan["objects"].first.dig("definition","animation")
  end
  def test_presets_create_independent_productions_and_add_scenes_without_replacing_existing_work
    key=SecureRandom.uuid
    result=preset("show_bible/nerd_world_order_series",mode:"new_project",name:"NWO",request_key:key)
    assert_equal result,preset("show_bible/nerd_world_order_series",mode:"new_project",name:"NWO",request_key:key)
    scenes=StudioProject.find(result[:project_id]).studio_scenes
    assert_equal %w[cold_open assembly manifesto],scenes.map(&:name)
    assert_equal [192,240,192],scenes.map { |s| s.settings["frame_end"] }
    assert_equal [65,65,85],scenes.map { |s| s.scene_objects.where(object_type:"camera").last.definition["lens"] }
    assert_equal 0,@scene.scene_objects.count
    cube=@scene.scene_objects.create!(name:"Keep",object_type:"cube",definition:{"scale"=>[1,1,1]})
    added=preset("show_bible/game_show",mode:"new_scenes")
    assert_equal 3,added["scene_ids"].length
    assert_equal "Keep",cube.reload.name
    assert_equal 4,@project.studio_scenes.count
  end
  def test_idempotency_stale_saves_and_tenant_scope
    key=SecureRandom.uuid;version=@scene.lock_version
    result=preset("camera/full_frame_85mm_portrait",request_key:key)
    repeated=preset("camera/full_frame_85mm_portrait",request_key:key)
    assert_equal result,repeated
    assert_equal 1,@scene.scene_objects.count
    assert_raises(ArgumentError) { preset("camera/sports_box_70mm",request_key:key) }
    assert_raises(ArgumentError) { preset("camera/sports_box_70mm",lock_version:version) }
    assert_equal 1,@scene.scene_objects.count
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private")
    @alice.update!(role:"member")
    assert_raises(ActiveRecord::RecordNotFound) { preset("camera/sports_box_70mm",scene_id:foreign.studio_scenes.first.id) }
  end
  def test_missing_assets_are_not_replaced_with_fake_media
    assert_raises(ArgumentError) { preset("audio/reality_music_bed") }
    assert_equal 0,@scene.scene_objects.count
    assert_nil @scene.reload.settings["blender_presets"]
  end
  def test_format_and_material_presets_edit_saved_blender_values
    cube=@scene.scene_objects.create!(name:"Target",object_type:"cube",definition:{"scale"=>[1,1,1]})
    preset("materials/glamour_floor",object_id:cube.id)
    assert_equal 0.15,cube.reload.definition.dig("material","roughness")
    preset("video/broadcast_sports_1080p")
    assert_equal 60,@scene.reload.settings["fps"]
    assert_in_delta 59.94,60/@scene.settings["fps_base"],0.0001
  end
  def test_json_presets_compose_inside_native_projects_without_changing_the_source
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("native-json-compose-") do |root|
      asset=imported_native(native_fixture(root));source=asset.native.blob.download
      created=action("blender_template_use",asset_id:asset.id,source_scene:"Native Stage",request_key:SecureRandom.uuid)
      scene=StudioScene.find(created[:scene_id])
      preset("camera/hero_push_in",scene_id:scene.id,lock_version:scene.lock_version)
      preset("base/blender_graph",scene_id:scene.id,lock_version:scene.reload.lock_version)
      manifest=Blender::ManifestBuilder.new(scene.reload).call;manifest["outputs"]={"blend"=>true}
      op=scene.studio_operations.create!(studio_project:scene.studio_project,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"pending",intent:{"user_id"=>@alice.id},manifest:manifest)
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      Rails.stub(:root,Pathname(ROOT)) do
        result=Studio::Providers::BlenderProvider.new(op).call
        script="import bpy; s=bpy.context.scene; assert s.world.name=='NativeWorld'; assert 'Native Geometry' in bpy.data.node_groups; assert 'PreservedRig' in s.objects; assert s.camera.data.lens==85; assert len([t for t in bpy.data.texts if t.name.startswith('LightekPreset_')])==2; print('NATIVE_JSON_COMPOSE_PASS')"
        out=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background",result.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-exit-code","1","--python-expr",script],timeout:60)
        assert_includes out,"NATIVE_JSON_COMPOSE_PASS"
      end
      assert_equal source,asset.native.blob.download
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_native_blender_output_contains_cameras_motion_nodes_titles_materials_and_markers
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    %w[camera/full_frame_85mm_portrait base/blender_graph graphics/sports_scorebug_modern materials/broadcast_core geo/prestige_set episode/cold_open_60s video/broadcast_sports_1080p].each { |key| preset(key) }
    @scene.reload.update!(settings:@scene.settings.merge("resolution_x"=>64,"resolution_y"=>64,"samples"=>1))
    op=@project.studio_operations.create!(studio_scene:@scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"pending",intent:{"user_id"=>@alice.id},manifest:Blender::ManifestBuilder.new(@scene.reload).call)
    Dir.mktmpdir("json-preset-render-") do |root|
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      Rails.stub(:root,Pathname(ROOT)) do
        result=Studio::Providers::BlenderProvider.new(op).call
        script=<<~PY
          import bpy,json
          s=bpy.context.scene
          print('PRESET_PROOF='+json.dumps({'lens':s.camera.data.lens,'sensor':s.camera.data.sensor_width,'dof':s.camera.data.dof.use_dof,'fstop':s.camera.data.dof.aperture_fstop,'fps':s.render.fps/s.render.fps_base,'markers':len(s.timeline_markers),'texts':[o.data.body for o in s.objects if o.type=='FONT'],'nodes':[n.bl_idname for n in s.node_tree.nodes],'groups':[n.name for n in bpy.data.node_groups],'materials':[m.name for m in bpy.data.materials],'sources':len([t for t in bpy.data.texts if t.name.startswith('LightekPreset_')]),'animated':bool(s.camera.animation_data)}))
        PY
        out=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background",result.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-expr",script],timeout:60)
        proof=JSON.parse(out.lines.find { |l| l.start_with?("PRESET_PROOF=") }.delete_prefix("PRESET_PROOF="))
        assert_equal 85,proof["lens"];assert_equal 36,proof["sensor"];assert proof["dof"];assert_in_delta 1.8,proof["fstop"],0.0001
        assert_in_delta 59.94,proof["fps"],0.001
        assert_equal 6,proof["markers"];assert_includes proof["texts"],"HOME 0 - 0 AWAY"
        assert_includes proof["nodes"],"CompositorNodeGlare";assert_includes proof["groups"],"GEO_STAGE"
        assert_includes proof["materials"],"GlossBlack";assert_equal 7,proof["sources"];assert proof["animated"]
        assert op.artifacts.find_by!(kind:"blend").file.attached?
      end
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
end
