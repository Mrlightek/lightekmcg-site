require_relative "studio_music_checks"
class StudioMusicPatternsTest < StudioMusicTest
  StudioMusicTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def pattern_score
    data=score.deep_stringify_keys
    data["version"]=2
    data["patterns"]=[{"id"=>"pattern1","name"=>"Verse groove","bars"=>1,"tracks"=>[{"track_id"=>"bass","notes"=>[{"beat"=>0,"length"=>1,"pitch"=>40,"velocity"=>0.8}]}]}]
    data["playlist"]=[{"id"=>"placement1","pattern_id"=>"pattern1","bar"=>1,"repeat"=>2,"transpose"=>12,"velocity"=>0.5,"muted"=>false}]
    data
  end
  def test_patterns_save_edit_and_expand_every_linked_placement
    result=save_score(pattern_score)
    assert_equal 2,result[:composition]["version"]
    expanded=Studio::Music::Patterns.expand(result[:composition]).find{|t|t["id"]=="bass"}["notes"]
    assert_equal [0,4,8],expanded.map{|n|n["beat"]}
    assert_equal [36,52,52],expanded.map{|n|n["pitch"]}
    assert_in_delta 0.4,expanded[1]["velocity"],1e-8
    changed=pattern_score;changed["patterns"][0]["tracks"][0]["notes"][0]["pitch"]=42
    saved=save_score(changed)
    assert_equal [36,54,54],Studio::Music::Patterns.expand(saved[:composition]).find{|t|t["id"]=="bass"}["notes"].map{|n|n["pitch"]}
  end
  def test_patterns_reject_missing_channels_patterns_versions_duplicates_and_bounds
    mutations=[
      ->(s){s["version"]=1},->(s){s["patterns"][0]["tracks"][0]["track_id"]="missing"},
      ->(s){s["playlist"][0]["pattern_id"]="missing"},->(s){s["playlist"][0]["bar"]=3},
      ->(s){s["playlist"][0]["repeat"]=1.5},->(s){s["patterns"][0]["bars"]=17},
      ->(s){s["patterns"][0]["tracks"][0]["notes"][0]["length"]=5},
      ->(s){s["playlist"]<<s["playlist"][0].deep_dup},->(s){s["patterns"]<<s["patterns"][0].deep_dup},
      ->(s){s["playlist"][0]["bar"]=0;s["patterns"][0]["tracks"][0]["notes"][0]["pitch"]=36;s["playlist"][0]["transpose"]=0},
      ->(s){s["patterns"][0]["tracks"][0]["notes"][0]["pitch"]=120},->(s){s["playlist"][0]["velocity"]=Float::NAN}
    ]
    mutations.each{|mutate|data=pattern_score;mutate.call(data);assert_raises(ArgumentError){save_score(data)}}
  end
  def test_patterns_muting_and_episode_copies_preserve_editable_source
    data=pattern_score;data["playlist"][0]["muted"]=true
    saved=save_score(data)
    assert_equal 1,Studio::Music::Patterns.expand(saved[:composition]).find{|t|t["id"]=="bass"}["notes"].length
    template=action("template_save",project_id:@project.id,name:"Song template",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Episode score",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal @scene.reload.settings["music"],copy.settings["music"]
    changed=copy.settings["music"].deep_dup;changed["patterns"][0]["name"]="New verse"
    save_score(changed,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal "Verse groove",@scene.reload.settings.dig("music","patterns",0,"name")
  end
  def test_patterns_expansion_is_bounded_before_large_repeat_allocation
    data=pattern_score;data["bars"]=32;data["tempo"]=120;data["playlist"][0].merge!("bar"=>0,"repeat"=>32,"transpose"=>0)
    data["patterns"][0]["tracks"][0]["notes"]=(0...1024).map{|i|{"beat"=>(i/128)*0.25,"length"=>0.125,"pitch"=>i%128,"velocity"=>0.5}}
    assert_raises(ArgumentError){save_score(data)}
  end
  def test_patterns_cannot_save_music_to_a_different_site
    assert_raises(ActiveRecord::RecordNotFound){save_score(pattern_score,site_id:@other_site.id)}
  end
end
