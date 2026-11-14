require_relative "studio_music_checks"
class StudioMusicAutomationTest < StudioMusicTest
  StudioMusicTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def automated_score
    score.deep_stringify_keys.merge("version"=>3,"automation"=>[{"track_id"=>"bass","parameter"=>"gain","enabled"=>true,"points"=>[{"beat"=>16,"value"=>0,"curve"=>"linear"},{"beat"=>0,"value"=>0.7,"curve"=>"hold"}]}])
  end
  def test_automation_saves_sorted_points_preserves_patterns_and_independent_episode_sources
    data=automated_score
    data["patterns"]=[{"id"=>"groove","name"=>"Groove","bars"=>1,"tracks"=>[]}]
    data["playlist"]=[{"id"=>"first","pattern_id"=>"groove","bar"=>1,"repeat"=>1,"transpose"=>0,"velocity"=>1,"muted"=>false}]
    saved=save_score(data)
    lane=saved[:composition]["automation"].sole
    assert_equal [0,16],lane["points"].map{|point|point["beat"]}
    assert_equal 3,saved[:composition]["version"]
    assert_equal "groove",saved[:composition]["playlist"].sole["pattern_id"]
    template=action("template_save",project_id:@project.id,name:"Automated show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Automated episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id])
    assert_equal @scene.reload.settings["music"],copy.settings["music"]
    revised=copy.settings["music"].deep_dup;revised["automation"][0]["enabled"]=false
    save_score(revised,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal true,@scene.reload.settings.dig("music","automation",0,"enabled")
    assert_equal false,copy.reload.settings.dig("music","automation",0,"enabled")
  end
  def test_automation_rejects_invalid_references_points_curves_bounds_and_old_versions_without_writing
    save_score(automated_score);original=@scene.reload.settings["music"]
    mutations=[->(s){s["version"]=2},->(s){s["version"]=1},->(s){s["automation"]={}},
      ->(s){s["automation"][0]["track_id"]="foreign"},->(s){s["automation"][0]["parameter"]="tempo"},
      ->(s){s["automation"]<<s["automation"][0].deep_dup},->(s){s["automation"][0]["enabled"]="false"},
      ->(s){s["automation"][0]["points"][0]["beat"]=17},->(s){s["automation"][0]["points"][0]["beat"]=-1},
      ->(s){s["automation"][0]["points"][0]["value"]=1.6},->(s){s["automation"][0]["points"][0]["curve"]="cubic"},
      ->(s){s["automation"][0]["points"]<<s["automation"][0]["points"][0].deep_dup},
      ->(s){s["automation"][0]["points"]=nil},->(s){s["automation"][0]["points"]=[nil]},
      ->(s){s["automation"][0]["points"][0]["value"]=Float::NAN},
      ->(s){s["automation"][0]["points"]=(0..128).map{|i|{"beat"=>i/16.0,"value"=>0.5}}}]
    mutations.each{|mutate|data=automated_score;mutate.call(data);assert_raises(ArgumentError){save_score(data)}}
    assert_equal original,@scene.reload.settings["music"]
  end
  def test_automation_parameter_limits_and_bypassed_lanes_still_validate
    {"gain"=>[0,1.5],"pan"=>[-1,1],"cutoff"=>[100,18000],"delay"=>[0,0.6]}.each do |param,(low,high)|
      data=automated_score;lane=data["automation"][0];lane["parameter"]=param;lane["enabled"]=false
      lane["points"]=[{"beat"=>0,"value"=>low},{"beat"=>16,"value"=>high}]
      assert_equal [low,high],save_score(data)[:composition]["automation"].sole["points"].map{|p|p["value"]}
      lane["points"][0]["value"]=low-0.01
      assert_raises(ArgumentError){save_score(data)}
    end
    assert_equal 1,save_score(score)[:composition]["version"]
    assert_equal 2,save_score(score.merge(version:2))[:composition]["version"]
  end
  def test_automation_total_point_budget
    data=automated_score;data["tracks"]=(0...16).map{|i|data["tracks"][1].merge("id"=>"channel#{i}")}
    data["automation"]=data["tracks"].flat_map do |track|
      %w[gain pan].map{|parameter|{"track_id"=>track["id"],"parameter"=>parameter,"enabled"=>true,"points"=>(0...128).map{|i|{"beat"=>i/8.0,"value"=>0.5}}}}
    end
    assert_raises(ArgumentError){save_score(data)}
    data["automation"]=data["automation"].first(16)
    assert_equal 2048,save_score(data)[:composition]["automation"].sum{|l|l["points"].length}
  end
end
