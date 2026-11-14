require_relative "studio_music_checks"
class StudioMusicMixerTest < StudioMusicTest
  StudioMusicTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def mixer_score
    data=score.deep_stringify_keys;data["version"]=4
    data["tracks"][0].merge!("bus_id"=>"drums","effects"=>[{"id"=>"channel_eq","kind"=>"eq","enabled"=>true,"params"=>{"low"=>3}}])
    data["mixer"]={"buses"=>[{"id"=>"drums","name"=>"Drum group","gain"=>0.6,"pan"=>-0.2,"muted"=>false,"solo"=>false,"effects"=>[{"id"=>"glue","kind"=>"compressor","enabled"=>false,"params"=>{}}]}],"master"=>{"gain"=>0.8,"effects"=>[{"id"=>"echo","kind"=>"delay","params"=>{"wet"=>0.2}}]}}
    data
  end
  def test_mixer_persists_routes_defaults_effect_order_and_independent_episode_sources
    saved=save_score(mixer_score)[:composition]
    assert_equal 4,saved["version"]
    assert_equal "drums",saved["tracks"][0]["bus_id"]
    assert_equal 0,saved["tracks"][0]["effects"][0]["params"]["mid"]
    assert_equal false,saved["mixer"]["buses"][0]["effects"][0]["enabled"]
    assert_equal 4,saved["mixer"]["buses"][0]["effects"][0]["params"]["ratio"]
    template=action("template_save",project_id:@project.id,name:"Mixed show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Mixed episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal saved,copy.settings["music"]
    changed=copy.settings["music"].deep_dup;changed["mixer"]["buses"][0]["effects"][0]["enabled"]=true
    save_score(changed,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal false,@scene.reload.settings.dig("music","mixer","buses",0,"effects",0,"enabled")
    assert_equal true,copy.reload.settings.dig("music","mixer","buses",0,"effects",0,"enabled")
  end
  def test_mixer_rejects_invalid_routing_effect_parameters_versions_and_budgets_without_writing
    save_score(mixer_score);before=@scene.reload.settings["music"]
    mutations=[->(s){s["version"]=3},->(s){s["tracks"][0]["bus_id"]="missing"},->(s){s["mixer"]=nil},
      ->(s){s["mixer"]["buses"]<<s["mixer"]["buses"][0].deep_dup},->(s){s["mixer"]["buses"][0]["output"]="drums"},
      ->(s){s["mixer"]["buses"][0]["gain"]=1.6},->(s){s["mixer"]["buses"][0]["muted"]="false"},
      ->(s){s["tracks"][0]["effects"][0]["kind"]="arbitrary_plugin"},->(s){s["tracks"][0]["effects"][0]["params"]["low"]=25},
      ->(s){s["tracks"][0]["effects"][0]["params"]["unknown"]=0},->(s){s["tracks"][0]["effects"][0]["enabled"]=nil},
      ->(s){s["tracks"][0]["effects"]<<s["tracks"][0]["effects"][0].deep_dup},
      ->(s){s["mixer"]["master"]["effects"]=(0...5).map{|i|{"id"=>"e#{i}","kind"=>"eq"}}},
      ->(s){s["mixer"]["master"]["effects"][0]["params"]["feedback"]=0.9},
      ->(s){s["mixer"]["buses"]=(0...9).map{|i|{"id"=>"bus#{i}"}}},
      ->(s){s["tracks"][0]["effects"][0]["params"]["low"]=Float::NAN}]
    mutations.each{|mutate|data=mixer_score;mutate.call(data);assert_raises(ArgumentError){save_score(data)}}
    assert_equal before,@scene.reload.settings["music"]
    data=mixer_score;data["tracks"]=(0...9).map{|i|data["tracks"][0].merge("id"=>"t#{i}","effects"=>(0...4).map{|j|{"id"=>"e#{j}","kind"=>"eq"}})}
    assert_raises(ArgumentError){save_score(data)}
  end
  def test_mixer_preserves_pattern_and_automation_sources_and_old_versions
    data=mixer_score;data["automation"]=[{"track_id"=>"kick","parameter"=>"gain","enabled"=>true,"points"=>[{"beat"=>0,"value"=>0.5}]}]
    data["patterns"]=[{"id"=>"verse","bars"=>1,"tracks"=>[{"track_id"=>"kick","notes"=>[{"beat"=>1,"length"=>0.1}]}]}]
    data["playlist"]=[{"id"=>"clip","pattern_id"=>"verse","bar"=>1}]
    saved=save_score(data)[:composition]
    assert_equal "verse",saved["playlist"].sole["pattern_id"]
    assert_equal 0.5,saved["automation"].sole["points"].sole["value"]
    assert_equal [0,5],Studio::Music::Patterns.expand(saved)[0]["notes"].map{|n|n["beat"]}
    [1,2,3].each{|version|assert_equal version,save_score(score.merge(version:version))[:composition]["version"]}
  end
end
