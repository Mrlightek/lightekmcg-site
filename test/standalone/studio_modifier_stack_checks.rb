require_relative "studio_authoring_checks"
class StudioModifierStackTest < StudioAuthoringTest
  StudioAuthoringTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def test_modifier_stack_commands_are_saved_ordered_idempotent_and_reversible
    mesh.update!(definition:mesh.definition.merge("native_original"=>{"modifiers"=>[{"name"=>"Rig","type"=>"ARMATURE"},{"name"=>"Source Bevel","type"=>"BEVEL"}]}))
    author(mesh,{kind:"modifier",name:"Thickness",type:"SOLIDIFY",properties:{thickness:0.25}})
    payload={request_key:SecureRandom.uuid,lock_version:@scene.reload.lock_version}
    first=author(mesh,{kind:"modifier_move",name:"Thickness",index:0},**payload)
    assert_equal first,author(mesh,{kind:"modifier_move",name:"Thickness",index:0},**payload)
    author(mesh,{kind:"modifier_state",name:"Source Bevel",show_viewport:false,show_render:true})
    author(mesh,{kind:"modifier_remove",name:"Source Bevel"})
    projection=Studio::NativeBlender::Authoring.new(nil,nil)
    assert_equal ["Thickness","Rig"],projection.modifier_stack(mesh.reload).map { |m| m["name"] }
    author(mesh,{},operation:"undo")
    assert_equal ["Thickness","Rig","Source Bevel"],projection.modifier_stack(mesh.reload).map { |m| m["name"] }
    author(mesh,{},operation:"redo")
    assert_equal ["Thickness","Rig"],projection.modifier_stack(mesh.reload).map { |m| m["name"] }
    author(mesh,{kind:"modifier",name:"Source Bevel",type:"DECIMATE",properties:{ratio:0.5}})
    assert_equal "DECIMATE",projection.modifier_stack(mesh.reload).last["type"]
    manifest=Blender::ManifestBuilder.new(@scene.reload).call
    assert_equal mesh.definition["authoring_commands"],manifest.dig("scene","objects").find { |o| o["id"].to_s==mesh.id.to_s }.dig("definition","authoring_commands")
  end
  def test_modifier_stack_rejects_missing_unsupported_invalid_stale_and_non_mesh_edits
    mesh.update!(definition:mesh.definition.merge("modifiers"=>[{"name"=>"Geometry","type"=>"NODES"},{"name"=>"Edge","type"=>"BEVEL"}]))
    bad=[{kind:"modifier_remove",name:"Missing"},{kind:"modifier_remove",name:"Geometry"},{kind:"modifier_move",name:"Edge",index:2},{kind:"modifier_move",name:"Edge",index:0.5},{kind:"modifier",name:"x"*64,type:"BEVEL",properties:{width:0.1}},{kind:"modifier_state",name:"Edge",show_render:"false"},{kind:"modifier_state",name:"Edge"},{kind:"modifier",name:"Geometry",type:"BEVEL",properties:{width:0.1}},{kind:"modifier",name:"Edge",type:"BEVEL",properties:{segments:9}},{kind:"modifier",name:"Edge",type:"BEVEL",properties:{segments:1.5}}]
    bad.each { |command| assert_raises(ArgumentError) { author(mesh,command) } }
    assert_nil mesh.reload.definition["authoring_commands"]
    stale=@scene.reload.lock_version;author(mesh,{kind:"modifier_state",name:"Edge",show_render:false})
    assert_raises(ArgumentError) { author(mesh,{kind:"modifier_remove",name:"Edge"},lock_version:stale) }
    arm=@scene.scene_objects.create!(name:"Rig",object_type:"native_object",definition:{native_type:"ARMATURE"})
    assert_raises(ArgumentError) { author(arm,{kind:"modifier_remove",name:"Edge"}) }
    assert_equal 1,mesh.reload.definition["authoring_commands"].length
  end
  def test_modifier_stack_projection_preserves_geometry_node_positions_and_caps_new_entries
    author(mesh,{kind:"node_add",scope:"geometry",modifier:"Shape graph",name:"Input",type:"NodeGroupInput"})
    author(mesh,{kind:"modifier",name:"Edges",type:"BEVEL",properties:{width:0.1}})
    author(mesh,{kind:"modifier_move",name:"Edges",index:0})
    assert_equal ["Edges","Shape graph"],Studio::NativeBlender::Authoring.new(nil,nil).modifier_stack(mesh.reload).map { |m| m["name"] }
    mesh.update!(definition:{"modifiers"=>Array.new(64) { |i| {"name"=>"Bevel #{i}","type"=>"BEVEL"} }})
    assert_raises(ArgumentError) { author(mesh,{kind:"modifier",name:"Extra",type:"BEVEL",properties:{width:0.1}}) }
    author(mesh,{kind:"modifier",name:"Bevel 0",type:"BEVEL",properties:{width:0.2}})
    assert_equal 1,mesh.reload.definition["authoring_commands"].length
  end
  def test_modifier_stack_real_native_render_export_reopens_and_preserves_original_source
    skip "Set LIGHTEK_TEST_BLENDER=1" unless ENV["LIGHTEK_TEST_BLENDER"]=="1"
    Dir.mktmpdir("modifier-stack-") do |root|
      source=native_fixture(root)
      setup="import bpy; c=bpy.data.objects['NativeCube']; m=c.modifiers.new('Source Bevel','BEVEL'); m.width=0.03; m.segments=2; m.keyframe_insert(data_path='width',frame=1); m.width=0.2; m.keyframe_insert(data_path='width',frame=3); m.driver_add('show_viewport').driver.expression='1'; bpy.context.scene.frame_set(1); bpy.ops.wm.save_as_mainfile(filepath=#{source.inspect})"
      Studio::MediaProcess.run!(["blender","--background",source,"--disable-autoexec","--python-exit-code","1","--python-expr",setup],timeout:60)
      asset=imported_native(source);original=asset.native.blob.download
      opened=action("blender_template_use",asset_id:asset.id,source_scene:"Native Stage",request_key:SecureRandom.uuid)
      scene=StudioScene.find(opened[:scene_id]);cube=scene.scene_objects.find_by!(name:"NativeCube")
      imported=cube.definition.fetch("modifier_stack").find { |m| m["name"]=="Source Bevel" }
      assert imported["show_viewport"];assert_equal 2,imported.dig("properties","segments")
      author(cube,{kind:"modifier",name:"Source Bevel",type:"BEVEL",properties:{width:0.08,segments:3}})
      author(cube,{kind:"modifier",name:"Thickness",type:"SOLIDIFY",properties:{thickness:0.25}})
      author(cube,{kind:"modifier_move",name:"Thickness",index:0})
      author(cube,{kind:"modifier_state",name:"Source Bevel",show_viewport:false,show_render:true})
      author(cube,{kind:"modifier_remove",name:"Source Bevel"});author(cube,{},operation:"undo");author(cube,{},operation:"redo");author(cube,{},operation:"undo")
      manifest=Blender::ManifestBuilder.new(scene.reload).call;manifest["scene"]["settings"].merge!("resolution_x"=>64,"resolution_y"=>64,"samples"=>1,"frame_current"=>3)
      manifest["outputs"]={"blend"=>true,"glb"=>true,"preview"=>true,"authoring"=>true}
      op=scene.studio_operations.create!(studio_project:scene.studio_project,operation_type:"build_scene",provider:"blender",capability:"studio.workspace.blender.authoring.preview",status:"running",intent:{user_id:@alice.id},manifest:manifest)
      previous=ENV["BLENDER_OUTPUT_ROOT"];ENV["BLENDER_OUTPUT_ROOT"]=File.join(root,"out")
      result=Rails.stub(:root,Pathname(ROOT)) { Studio::Providers::BlenderProvider.new(op).call }
      inventory=JSON.parse(File.read(result.output_directory.join("authoring.json"))).fetch(cube.id.to_s).fetch("modifier_stack")
      assert_equal ["Thickness","Native nodes","Source Bevel"],inventory.map { |m| m["name"] }
      refute inventory.last["show_viewport"];assert inventory.last["show_render"];assert_equal 3,inventory.last.dig("properties","segments")
      check="import bpy; c=bpy.data.objects['NativeCube']; bpy.context.scene.frame_set(3); assert [m.name for m in c.modifiers]==['Thickness','Native nodes','Source Bevel']; assert c.modifiers['Source Bevel'].show_viewport==False; assert c.modifiers['Source Bevel'].show_render==True; assert abs(c.modifiers['Source Bevel'].width-0.08)<1e-6; assert len(c.data.vertices)==8; assert len(c.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.polygons)>6; assert 'PreservedRig' in bpy.data.objects; print('MODIFIER_REOPEN_PASS')"
      output=Studio::MediaProcess.run!(["blender","--background",result.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-exit-code","1","--python-expr",check],timeout:60)
      assert_includes output,"MODIFIER_REOPEN_PASS";assert File.size?(result.output_directory.join("preview.png"));assert_equal "glTF",File.binread(result.output_directory.join("scene.glb"),4)
      glb=File.binread(result.output_directory.join("scene.glb"));gltf=JSON.parse(glb.byteslice(20,glb.byteslice(12,4).unpack1("V")))
      node=gltf.fetch("nodes").find { |n| n["name"]=="NativeCube" };primitive=gltf.fetch("meshes").fetch(node.fetch("mesh")).fetch("primitives").first
      assert gltf.fetch("accessors").fetch(primitive.fetch("attributes").fetch("POSITION")).fetch("count")>24,"Authoring GLB must contain evaluated solidify geometry, not the base cube"
      remove="import bpy,sys; sys.path.insert(0,#{File.join(ROOT,'blender').inspect}); import authoring; c=bpy.data.objects['NativeCube']; authoring.apply(c,[{'kind':'modifier_remove','name':'Source Bevel'}]); assert c.modifiers.get('Source Bevel') is None; assert c.modifiers.get('Native nodes') is not None; print('MODIFIER_REMOVE_PASS')"
      removed=Studio::MediaProcess.run!(["blender","--background",result.output_directory.join("scene.blend").to_s,"--disable-autoexec","--python-exit-code","1","--python-expr",remove],timeout:60)
      assert_includes removed,"MODIFIER_REMOVE_PASS"
      assert_equal original,asset.native.blob.download
    ensure
      ENV["BLENDER_OUTPUT_ROOT"]=previous
    end
  end
end
