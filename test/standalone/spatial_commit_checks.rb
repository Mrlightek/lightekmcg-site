# frozen_string_literal: true
require_relative "studio_library_checks"
require File.join(ROOT,"app/services/studio/spatial/commit")
class SpatialCommitTest < StudioLibraryTest
  StudioLibraryTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @access=Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id)
    @camera=@scene.scene_objects.create!(name:"RTC camera",object_type:"camera",definition:{"location"=>[0,0,2],"rotation"=>[0,0,0],"scale"=>[1,1,1],"lens"=>50})
  end
  def command
    {"type"=>"CAMERA_UPDATE","message_id"=>SecureRandom.uuid,"scene_revision"=>@scene.reload.lock_version,"payload"=>{"camera_id"=>@camera.id.to_s,"mode"=>"commit","role"=>"shot","focal_length_mm"=>85}}
  end
  def test_scene_revision_receipts_and_stale_save_rollback
    edit=command;revision=@scene.lock_version
    result=Studio::Spatial::Commit.call(@access,@scene.id,edit)
    assert_equal revision+1,result[:revision];assert_equal 85,@camera.reload.definition["lens"]
    assert_equal result,Studio::Spatial::Commit.call(@access,@scene.id,edit)
    assert_equal revision+1,@scene.reload.lock_version
    edit=command;edit["scene_revision"]=revision;edit["payload"]["focal_length_mm"]=30
    assert_raises(ArgumentError){Studio::Spatial::Commit.call(@access,@scene.id,edit)}
    assert_equal 85,@camera.reload.definition["lens"]
  end
  def test_forbidden_viewer_commit_invalid_matrix_and_receipt_tampering
    edit=command;edit["payload"]["role"]="viewer"
    assert_raises(ArgumentError){Studio::Spatial::Commit.call(@access,@scene.id,edit)}
    edit=command;edit["payload"]["camera_world_matrix"]=[0]*16
    assert_raises(ArgumentError){Studio::Spatial::Commit.call(@access,@scene.id,edit)}
    edit=command;Studio::Spatial::Commit.call(@access,@scene.id,edit);edit["payload"]["focal_length_mm"]=100
    assert_raises(ArgumentError){Studio::Spatial::Commit.call(@access,@scene.id,edit)}
  end
end
