# frozen_string_literal: true
require_relative "studio_creation_checks"
require File.join(ROOT,"app/services/studio/billing/quote")
class StudioAuthoringTest < StudioCreationTest
  StudioCreationTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def author(object,command={},**payload)
    action("blender_authoring_edit",**{scene_id:object.studio_scene_id,object_id:object.id,lock_version:object.studio_scene.reload.lock_version,request_key:SecureRandom.uuid,command:command}.merge(payload))
  end
  def mesh
    @mesh||=@scene.scene_objects.create!(name:"Editable",object_type:"cube",definition:{location:[0,0,0],rotation:[0,0,0],scale:[1,1,1]})
  end
  def test_authoring_commands_validate_scope_numbers_and_keep_other_tenants_private
    [{kind:"sculpt",center:[0,0,0],delta:[0,0,1],radius:0},{kind:"mesh_subdivide",cuts:20},{kind:"node_add",scope:"material",name:"Execute",type:"PythonNode"},{kind:"keyframe",location:[Float::INFINITY,0,0],frame:1}].each do |cmd|
      assert_raises(ArgumentError) { author(mesh,cmd) }
    end
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Private").studio_scenes.first
    @alice.update!(role:"member")
    assert_raises(ActiveRecord::RecordNotFound) { author(mesh,{kind:"mesh_translate",delta:[1,0,0]},scene_id:foreign.id) }
    assert_nil mesh.reload.definition["authoring_commands"]
  end
  def test_authoring_receipts_undo_redo_and_stale_saves_are_atomic
    payload={request_key:SecureRandom.uuid,lock_version:@scene.lock_version}
    first=author(mesh,{kind:"mesh_extrude",indices:[0],delta:[0,0,1]},**payload)
    assert_equal first,author(mesh,{kind:"mesh_extrude",indices:[0],delta:[0,0,1]},**payload)
    assert_equal 1,mesh.reload.definition["authoring_commands"].length
    assert_raises(ArgumentError) { author(mesh,{kind:"mesh_delete",indices:[0]},lock_version:payload[:lock_version]) }
    assert_equal 1,mesh.reload.definition["authoring_commands"].length
    author(mesh,{},operation:"undo");assert_empty mesh.reload.definition["authoring_commands"]
    author(mesh,{},operation:"redo");assert_equal 1,mesh.reload.definition["authoring_commands"].length
    author(mesh,{},operation:"undo");author(mesh,{kind:"mesh_smooth",indices:[0],amount:0.2,iterations:1})
    assert_raises(ArgumentError) { author(mesh,{},operation:"redo") }
  end
  def test_authoring_rig_tools_and_weights_require_appropriate_objects
    assert_raises(ArgumentError) { author(mesh,{kind:"bone_pose",bone:"Bone",rotation:[0,0,10]}) }
    assert_raises(ArgumentError) { author(mesh,{kind:"weight",group:"Bone",indices:[],weight:1}) }
    arm=@scene.scene_objects.create!(name:"Rig",object_type:"native_object",definition:{native_type:"ARMATURE",blender_object_name:"Rig"})
    author(arm,{kind:"bone_add",name:"Control",head:[0,0,0],tail:[0,0,1]})
    author(arm,{kind:"bone_pose",bone:"Control",rotation:[0,0,30],frame:12})
    assert_equal 2,arm.reload.definition["authoring_commands"].length
    assert_equal 12,arm.definition["authoring_commands"].last["frame"]
    assert_raises(ArgumentError) { author(arm,{kind:"mesh_translate",delta:[0,0,1]}) }
  end
  def test_authoring_preview_requests_real_geometry_and_does_not_mutate_the_source
    author(mesh,{kind:"mesh_subdivide",cuts:1})
    result=action("blender_authoring_preview",scene_id:@scene.id)
    op=StudioOperation.find(result[:operation_id])
    assert_equal({"glb"=>true,"preview"=>true,"authoring"=>true},op.manifest["outputs"])
    assert_equal "studio.workspace.blender.authoring.preview",op.capability
    assert_equal @scene.reload.settings["native_revision"],op.metadata["native_revision"]
    assert op.manifest.dig("scene","settings","resolution_x")<=320
  end
  def test_authoring_movie_quote_uses_animation_output_and_bounds_the_shot
    @scene.update!(settings:@scene.settings.merge("frame_start"=>1,"frame_end"=>3000))
    assert_raises(ArgumentError) { action("render_quote",scene_id:@scene.id,output:"movie") }
    assert_equal 0,@scene.studio_operations.count
    @scene.update!(settings:@scene.settings.merge("frame_end"=>3))
    Studio::Billing::Quote.stub(:call,->(**_args){{}}) do
      result=action("render_quote",scene_id:@scene.id,output:"movie")
      operation=StudioOperation.find(result[:operation_id])
      assert operation.manifest.dig("outputs","animation")
      assert operation.manifest.dig("outputs","blend")
      refute operation.manifest.dig("outputs","preview")
      assert_equal "awaiting_payment",operation.status
    end
  end
  def test_authoring_real_native_mesh_sculpt_rig_nodes_and_keyframes_survive_export
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("authoring-native-") do |root|
      source=native_fixture(root);asset=imported_native(source);original=asset.native.blob.download
      opened=action("blender_template_use",asset_id:asset.id,source_scene:"Native Stage",request_key:SecureRandom.uuid)
      scene=StudioScene.find(opened[:scene_id]);cube=scene.scene_objects.find_by!(name:"NativeCube");rig=scene.scene_objects.find_by!(name:"PreservedRig")
      assert cube.definition["mesh"]
      author(cube,{kind:"mesh_extrude",indices:[0],delta:[0,0,0.5]})
      author(cube,{kind:"sculpt",center:[0,0,0],radius:10,delta:[0.25,0,0]})
      author(cube,{kind:"modifier",name:"Studio bevel",type:"BEVEL",properties:{width:0.05,segments:2}})
      author(rig,{kind:"bone_add",name:"StudioControl",head:[0,0,0],tail:[0,0,1]})
      author(rig,{kind:"bone_pose",bone:"StudioControl",rotation:[0,0,30],frame:1})
      author(cube,{kind:"weight",group:"StudioControl",indices:[0,1],weight:0.75})
      author(cube,{kind:"node_add",scope:"material",slot:0,type:"ShaderNodeEmission",name:"Studio Glow"})
      author(cube,{kind:"node_value",scope:"material",slot:0,name:"Studio Glow",input:1,value:3})
      author(cube,{kind:"node_link",scope:"material",slot:0,from:"Studio Glow",output:0,to:"Material Output",input:0})
      author(cube,{kind:"keyframe",frame:1,location:[0,0,0]});author(cube,{kind:"keyframe",frame:3,location:[2,0,0]})
      scene.reload;manifest=Blender::ManifestBuilder.new(scene).call;manifest["outputs"]={"blend"=>true,"glb"=>true,"authoring"=>true}
      op=scene.studio_operations.create!(studio_project:scene.studio_project,operation_type:"build_scene",provider:"blender",capability:"studio.workspace.blender.asset.save",status:"running",intent:{user_id:@alice.id},manifest:manifest)
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=File.join(root,"out")
      result=Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(op).call }
      check="import bpy, math; c=bpy.data.objects['NativeCube']; assert len(c.data.vertices)==12; assert 'Studio bevel' in c.modifiers; assert 'StudioControl' in bpy.data.objects['PreservedRig'].pose.bones; assert abs(bpy.data.objects['PreservedRig'].pose.bones['StudioControl'].rotation_euler.z-math.radians(30))<0.001; assert abs(c.vertex_groups['StudioControl'].weight(0)-0.75)<0.001; assert c.data.materials[0].node_tree.nodes['Studio Glow'].inputs[1].default_value==3; bpy.context.scene.frame_set(3); assert abs(c.location.x-2)<0.001; print('AUTHORING_NATIVE_PASS')"
      output=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background",result.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-exit-code","1","--python-expr",check],timeout:60)
      assert_includes output,"AUTHORING_NATIVE_PASS"
      assert_equal "glTF",File.binread(result.output_directory.join("scene.glb"),4)
      inventory=JSON.parse(File.read(result.output_directory.join("authoring.json")))
      assert_equal 12,inventory.fetch(cube.id.to_s).dig("mesh","vertex_count")
      assert_equal original,asset.native.blob.download
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_authoring_real_uploaded_zip_preserves_rigs_resources_and_native_inventory
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("authoring-upload-") do |root|
      source=native_fixture(root);archive=File.join(root,"rig-and-stage.zip")
      Studio::MediaProcess.run!(["python3","-c","import sys,zipfile; z=zipfile.ZipFile(sys.argv[2],'w'); z.write(sys.argv[1],'project/rig.blend'); z.writestr('project/credits.txt','Test resource'); z.close()",source,archive],timeout:10)
      Api::LightekPwaController.allow_forgery_protection=true
      client=session_for;client.get "/test/csrf",headers:headers
      token=body(client).fetch("csrf_token")
      client.post "/api/lightek/pwa/uploads",headers:headers.merge("X-CSRF-Token"=>token),params:{file:Rack::Test::UploadedFile.new(archive,"application/zip"),purpose:"studio_asset"}
      assert_equal 201,client.response.status,client.response.body
      signed_id=body(client).fetch("signed_id");blob=ActiveStorage::Blob.find_signed!(signed_id)
      assert_equal @alice.id,blob.metadata["lightek_user_id"]
      assert_equal @site.id,blob.metadata["lightek_site_id"]
      asset=StudioAsset.find(action("asset_import",signed_id:signed_id,name:"Uploaded rig package",request_key:SecureRandom.uuid)[:asset_id])
      Rails.stub(:root,Pathname(ROOT)) { StudioAssetIngestJob.perform_now(asset.id) }
      asset.reload
      assert_equal "ready",asset.status
      assert asset.bundle.attached?
      assert_equal "project/rig.blend",asset.metadata["bundle_relative_source"]
      assert_equal 1,asset.metadata["authoring_version"]
      opened=action("blender_template_use",asset_id:asset.id,source_scene:"Native Stage",request_key:SecureRandom.uuid)
      scene=StudioScene.find(opened[:scene_id]);assert scene.blender_bundle.attached?
      assert scene.scene_objects.find_by!(name:"PreservedRig").definition["bones"]
      assert scene.scene_objects.find_by!(name:"NativeCube").definition["graphs"].any?
    end
  end
  def test_authoring_real_movie_export_is_a_playable_animation
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    created=create_asset;scene=StudioScene.find(created["scene_id"])
    scene.update!(settings:scene.settings.merge("render_engine"=>"CYCLES","samples"=>1,"resolution_x"=>64,"resolution_y"=>64,"frame_start"=>1,"frame_end"=>3,"fps"=>24))
    cube=scene.scene_objects.find(created["object_id"]);author(cube,{kind:"keyframe",frame:1,location:[0,0,1]});author(cube,{kind:"keyframe",frame:3,location:[2,0,1]})
    manifest=Blender::ManifestBuilder.new(scene.reload).call;manifest["outputs"]={"animation"=>true}
    op=scene.studio_operations.create!(studio_project:scene.studio_project,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"running",intent:{user_id:@alice.id},manifest:manifest)
    Dir.mktmpdir("authoring-movie-") do |root|
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=root
      result=Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(op).call }
      data=JSON.parse(Studio::MediaProcess.run!(["ffprobe","-v","error","-show_streams","-of","json",result.output_directory.join("movie.mp4").to_s],timeout:10))
      assert_equal "h264",data["streams"].first["codec_name"]
      assert_equal "3",data["streams"].first["nb_frames"]
      assert op.artifacts.find_by!(kind:"video").file.attached?
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
end
