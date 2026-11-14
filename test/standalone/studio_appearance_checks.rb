require_relative "studio_performance_checks"
require File.join(ROOT,"app/services/studio/native_blender/appearance")
class StudioAppearanceTest < StudioPerformanceTest
  StudioPerformanceTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def primitive
    @primitive||=@scene.scene_objects.create!(name:"Surface",object_type:"cube",definition:{"location"=>[0,0,1],"material"=>{"color"=>[0.2,0.3,0.4,1]}})
  end
  def status = action("look_status",scene_id:@scene.id)
  def apply_look(**extra)=action("look_save",scene_id:@scene.id,lock_version:@scene.reload.lock_version,look:{exposure:1,saturation:1.2},request_key:SecureRandom.uuid,**extra)
  def apply_material(**extra)
    action("material_save",scene_id:@scene.id,object_id:primitive.id,target:"",slot:0,lock_version:@scene.reload.lock_version,values:{roughness:0.2},request_key:SecureRandom.uuid,**extra)
  end
  def test_appearance_scene_look_is_saved_snapshotted_and_resettable
    primitive;apply_look
    assert_equal 1,status[:look]["exposure"]
    snapshot=Blender::ManifestBuilder.new(@scene.reload).call
    assert_equal 1,snapshot.dig("scene","settings","look","exposure")
    version=@scene.settings["native_revision"];apply_look(operation:"reset")
    assert_equal 0,status[:look]["exposure"]
    assert_equal({},@scene.reload.settings["look"])
    assert_operator @scene.settings["native_revision"],:>,version
    assert_equal 1,snapshot.dig("scene","settings","look","exposure")
  end
  def test_appearance_material_overrides_only_explicit_slots_and_inputs
    object=primitive;apply_material
    override=object.reload.definition["surface_overrides"].first
    assert_equal({"roughness"=>0.2},override["values"])
    assert_equal 0.2,status[:targets].find{|t|t[:object_id]==object.id}[:values]["roughness"]
    assert_equal [0.2,0.3,0.4,1],object.definition.dig("material","color")
    apply_material(values:{metallic:0.8})
    assert_equal({"roughness"=>0.2,"metallic"=>0.8},object.reload.definition.dig("surface_overrides",0,"values"))
    apply_material(operation:"reset")
    assert_empty object.reload.definition["surface_overrides"]
  end
  def test_appearance_material_slot_catalog_and_source_validation
    native=@scene.scene_objects.create!(name:"Native",object_type:"native_object",definition:{"native_original"=>{"location"=>[0,0,0]},"materials"=>[{"slot"=>0,"name"=>"First","editable"=>false},{"slot"=>2,"name"=>"Second","editable"=>true,"roughness"=>0.7,"linked_fields"=>["color"]}]})
    assert_equal [2],status[:targets].select{|t|t[:object_id]==native.id}.map{|t|t[:slot]}
    apply_material(object_id:native.id,slot:2)
    assert_equal 2,native.reload.definition.dig("surface_overrides",0,"slot")
    assert_raises(ArgumentError){apply_material(object_id:native.id,slot:0)}
    assert_raises(ArgumentError){apply_material(target:"arbitrary-mesh")}
  end
  def test_appearance_cast_materials_are_bound_to_the_registered_source_mesh
    actor=ready_actor;metadata=actor.metadata.deep_dup
    metadata["scenes"][0]["objects"][0]["definition"]["materials"]=[{"slot"=>0,"name"=>"Face color","editable"=>true,"color"=>[0.3,0.2,0.1,1],"roughness"=>0.6}]
    actor.update!(metadata:metadata)
    placed=action("cast_place",scene_id:@scene.id,asset_id:actor.id,lock_version:@scene.reload.lock_version,request_key:SecureRandom.uuid)
    object=SceneObject.find(placed["object_id"])
    target=status[:targets].find{|item|item[:object_id]==object.id}
    assert_equal "Face",target[:target]
    apply_material(object_id:object.id,target:"Face",values:{color:[0.4,0.1,0.1,1]})
    assert_equal "Face",object.reload.definition.dig("surface_overrides",0,"target")
    assert_raises(ArgumentError){apply_material(object_id:object.id,target:"Another actor's mesh")}
  end
  def test_appearance_rejects_nonfinite_values_foreign_scenes_and_stale_edits
    primitive
    assert_raises(ArgumentError){apply_look(look:{glow:2})}
    assert_raises(ArgumentError){apply_look(look:{exposure:Float::NAN})}
    assert_raises(ArgumentError){apply_material(values:{file:"/etc/passwd"})}
    assert_raises(ArgumentError){apply_material(values:{color:[1,0,0]})}
    assert_raises(ArgumentError){apply_material(lock_version:-1)}
    assert_raises(ActiveRecord::RecordNotFound){apply_material(site_id:@other_site.id)}
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Foreign").studio_scenes.first
    assert_raises(ActiveRecord::RecordNotFound){apply_look(scene_id:foreign.id)}
    assert_nil primitive.reload.definition["surface_overrides"]
  end
  def test_appearance_idempotence_and_independent_show_copies
    primitive;key=SecureRandom.uuid;version=@scene.reload.lock_version
    first=apply_material(request_key:key,lock_version:version)
    assert_equal first,apply_material(request_key:key,lock_version:version)
    assert_raises(ArgumentError){apply_material(request_key:key,values:{metallic:1})}
    apply_look
    template=action("template_save",project_id:@project.id,name:"Surface show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Another episode",request_key:SecureRandom.uuid)
    copied=StudioScene.find(episode[:scene_id]);copy=copied.scene_objects.find_by!(name:primitive.name)
    assert_nil copied.settings["look_receipts"]
    action("material_save",scene_id:copied.id,object_id:copy.id,target:"",slot:0,values:{roughness:0.9},lock_version:copied.lock_version,request_key:SecureRandom.uuid)
    assert_equal 0.2,primitive.reload.definition.dig("surface_overrides",0,"values","roughness")
    assert_equal 0.9,copy.reload.definition.dig("surface_overrides",0,"values","roughness")
  end
end
