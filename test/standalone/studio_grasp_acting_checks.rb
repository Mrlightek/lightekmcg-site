require_relative "studio_grasp_checks"
class StudioGraspActingTest < StudioGraspTest
  def grasp_version = 3
  def grasp(**extra)
    prepare(scene_template:"grasp_acting",camera_mode:"template",gesture:"still",dialogue:"There we go.",mechanics:{action:"grasp",version:3,target_id:"ball"},**extra)
  end
  def test_acting_grasp_owns_gaze_and_catalog_exposes_beats
    assert_raises(ArgumentError) { grasp(attention:{kind:"camera",start:0,end:8}) }
    row=action("character_scene_catalog",scene_id:@scene.id)[:scene_templates].find { |item| item[:key]=="grasp_acting" }
    assert_equal 3,row[:mechanics_targets].first[:version]
    assert_equal "template",row[:defaults]["camera_mode"]
  end
end
