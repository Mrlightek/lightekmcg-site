# frozen_string_literal: true
require_relative "media_preset_checks"
class BlenderAuthoringTest < NativeBlenderTest
  NativeBlenderTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def edit(scene,object,**payload)
    action("blender_object_save",scene_id:scene.id,object_id:object.id,lock_version:scene.reload.lock_version,**payload)
  end
  def native_scene(asset)
    result=action("blender_template_use",asset_id:asset.id,source_scene:"Native Stage",request_key:SecureRandom.uuid)
    StudioScene.find(result[:scene_id])
  end
  def test_missing_runtime_configuration_has_a_default_and_a_visible_health_failure
    previous=ENV.delete("STUDIO_ASSET_WORKER_IMAGE");render=ENV.delete("STUDIO_RENDER_WORKER_IMAGE")
    assert_equal "lightek/studio-media:20261101",Studio::NativeBlender::Runtime.image
    ENV["STUDIO_ASSET_WORKER_IMAGE"]="example/custom-blender:4"
    assert_equal "example/custom-blender:4",Studio::NativeBlender::Runtime.image(:render)
    Rails.stub(:env,ActiveSupport::StringInquirer.new("production")) do
      Studio::MediaProcess.stub(:run!,->(*_args,**_opts){raise "Missing engine"}) do
        health=action("blender_runtime_status")
        refute health[:ready];assert_includes health[:message],"deployment"
      end
    end
  ensure
    previous ? ENV["STUDIO_ASSET_WORKER_IMAGE"]=previous : ENV.delete("STUDIO_ASSET_WORKER_IMAGE")
    render ? ENV["STUDIO_RENDER_WORKER_IMAGE"]=render : ENV.delete("STUDIO_RENDER_WORKER_IMAGE")
  end
  def test_full_demo_install_is_idempotent_and_preserves_the_official_catalog_boundary
    first=action("blender_library_install")
    assert_equal 12,first[:imports].length
    assert_equal 12,StudioAsset.where(owner:@alice).count
    again=action("blender_library_install")
    assert_equal first,again
    assert_raises(ArgumentError) { action("blender_library_install",keys:["http://127.0.0.1/private"]) }
    assert_equal 12,StudioAsset.where(owner:@alice).count
  end
  def test_native_object_edit_rejects_stale_and_foreign_objects_and_can_restore_removals
    definition={"blender_object_name"=>"Cube","native_type"=>"MESH","location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1]}
    definition["native_original"]=definition.deep_dup
    object=@scene.scene_objects.create!(name:"Cube",object_type:"native_object",definition:definition)
    version=@scene.lock_version
    edit(@scene,object,properties:{location:[2,0,0]})
    assert_raises(ArgumentError) { action("blender_object_save",scene_id:@scene.id,object_id:object.id,lock_version:version,properties:{location:[9,0,0]}) }
    assert_equal [2,0,0],object.reload.definition["location"]
    @alice.update!(role:"member")
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Foreign")
    assert_raises(ActiveRecord::RecordNotFound) { action("blender_object_save",scene_id:foreign.studio_scenes.first.id,object_id:object.id,lock_version:0,properties:{location:[9,0,0]}) }
    edit(@scene,object,operation:"delete");assert object.reload.definition["native_deleted"]
    edit(@scene,object,operation:"restore");refute object.reload.definition["native_deleted"]
  end
  def test_native_object_edits_render_into_blender_and_keep_the_library_file_unchanged
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("native-object-authoring-") do |root|
      source=native_fixture(root)
      code="import bpy; obj=bpy.data.objects['NativeCube']; mod=obj.modifiers[0]; socket=mod.node_group.interface.new_socket(name='Detail',in_out='INPUT',socket_type='NodeSocketFloat'); socket.default_value=2; mod[socket.identifier]=2.0; lamp=bpy.data.objects.new('NativeLight',bpy.data.lights.new('NativeLightData','AREA')); bpy.context.scene.collection.objects.link(lamp); bpy.ops.wm.save_as_mainfile(filepath=#{source.inspect})"
      Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background",source,"--disable-autoexec","--python-exit-code","1","--python-expr",code],timeout:60)
      asset=imported_native(source);original=asset.native.blob.download
      assert_equal 1,asset.metadata["native_inventory_version"]
      scene=native_scene(asset)
      cube=scene.scene_objects.find_by!(object_type:"native_object",name:"NativeCube")
      light=scene.scene_objects.find_by!(name:"NativeLight")
      socket=cube.definition["node_inputs"].find { |i| i["name"]=="Detail" }
      assert socket
      edit(scene,cube,properties:{location:[4,2,1],material:{color:[1,0,0,1],roughness:0.8},node_inputs:[socket.merge("value"=>3.5)]})
      edit(scene,light,properties:{energy:250,size:4,color:[0.1,0.2,0.3]})
      duplicated=edit(scene,cube,operation:"duplicate");copy=SceneObject.find(duplicated[:object_id])
      assert_equal [5,2,1],copy.definition["location"]
      edit(scene,copy,operation:"delete")
      manifest=Blender::ManifestBuilder.new(scene.reload).call;manifest["outputs"]={"blend"=>true}
      op=scene.studio_operations.create!(studio_project:scene.studio_project,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"running",intent:{user_id:@alice.id},manifest:manifest)
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=File.join(root,"render")
      Rails.stub(:root,Pathname(ROOT)) do
        result=Studio::Providers::BlenderProvider.new(op).call
        check="import bpy; o=bpy.data.objects['NativeCube']; assert list(o.matrix_world.translation)==[4,2,1]; assert o.modifiers[0][#{socket['identifier'].inspect}]==3.5; assert abs(o.data.materials[0].node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value-0.8)<0.001; assert bpy.data.objects['NativeLight'].data.energy==250; assert bpy.data.objects[#{copy.name.inspect}].hide_render; assert 'Native Geometry' in bpy.data.node_groups; assert bpy.context.scene.world.name=='NativeWorld'; print('NATIVE_OBJECT_AUTHORING_PASS')"
        out=Studio::MediaProcess.run!([ENV.fetch("BLENDER_BIN","blender"),"--background",result.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-exit-code","1","--python-expr",check],timeout:60)
        assert_includes out,"NATIVE_OBJECT_AUTHORING_PASS"
      end
      assert_equal original,asset.native.blob.download
      assert_raises(ArgumentError) { edit(scene,cube,node_inputs:[{"modifier"=>"fake","identifier"=>"../x","value"=>2}],properties:{node_inputs:[{"modifier"=>"fake","identifier"=>"../x","value"=>2}]}) }
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
  def test_authoring_preview_runs_blender_at_bounded_resolution_without_render_checkout
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("native-preview-") do |root|
      scene=native_scene(imported_native(native_fixture(root)))
      result=action("blender_preview",scene_id:scene.id,frame:1,resolution_x:4096)
      op=StudioOperation.find(result[:operation_id])
      assert_equal({"preview"=>true},op.manifest["outputs"])
      assert op.manifest.dig("scene","settings","resolution_x")<=320
      assert_equal 2,op.manifest.dig("scene","settings","samples")
      assert_equal result[:operation_id],action("blender_preview",scene_id:scene.id)[:operation_id]
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=File.join(root,"render")
      Rails.stub(:root,Pathname(ROOT)) { StudioBlenderPreviewJob.perform_now(op.id) }
      assert_equal "completed",op.reload.status
      assert_empty op.cost_quote
      artifact=op.artifacts.find_by!(kind:"preview")
      assert artifact.file.attached?
      assert action("blender_preview",scene_id:scene.id,operation_id:op.id)[:url].start_with?("/rails/active_storage/")
      assert_equal 128,scene.reload.settings["resolution_x"],"Authoring limits must not change the final render settings"
      @alice.update!(role:"member")
      assert_raises(ActiveRecord::RecordNotFound) { action("blender_preview",scene_id:@scene.id,operation_id:op.id) }
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
end
