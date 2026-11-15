require_relative "studio_music_mixer_checks"
class StudioMusicBusAutomationTest < StudioMusicMixerTest
  StudioMusicMixerTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def bus_automated_score
    data=mixer_score;data["version"]=7
    data["scoring"]={"start"=>2,"cues"=>[{"id"=>"cue","name"=>"Entrance","time"=>3}]}
    # Deliberately use the same channel and bus ID: the target type is part of identity.
    data["mixer"]["buses"][0]["id"]="kick";data["tracks"][0]["bus_id"]="kick"
    data["automation"]=[{"track_id"=>"kick","parameter"=>"gain","points"=>[{"beat"=>0,"value"=>0.8}]},
      {"bus_id"=>"kick","parameter"=>"gain","points"=>[{"beat"=>16,"value"=>0},{"beat"=>0,"value"=>1}]},
      {"bus_id"=>"kick","parameter"=>"pan","points"=>[{"beat"=>0,"value"=>-1},{"beat"=>16,"value"=>1}]},
      {"master"=>true,"parameter"=>"gain","points"=>[{"beat"=>0,"value"=>1},{"beat"=>16,"value"=>0}]}]
    data
  end
  def test_bus_automation_saves_target_identity_sorted_curves_and_independent_episode
    saved=save_score(bus_automated_score)[:composition]
    assert_equal 7,saved["version"]
    assert_equal [0,16],saved["automation"][1]["points"].map{|p|p["beat"]}
    assert_equal "kick",saved["automation"][0]["track_id"]
    assert_equal "kick",saved["automation"][1]["bus_id"]
    assert_equal true,saved["automation"][3]["master"]
    assert_equal 2,saved["scoring"]["start"]
    template=action("template_save",project_id:@project.id,name:"Fading show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Fading episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal saved,copy.settings["music"]
    changed=copy.settings["music"].deep_dup;changed["automation"][3]["enabled"]=false
    save_score(changed,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal true,@scene.reload.settings.dig("music","automation",3,"enabled")
    assert_equal false,copy.reload.settings.dig("music","automation",3,"enabled")
  end
  def test_bus_automation_rejects_ambiguous_missing_old_and_unsupported_targets_without_writing
    before=save_score(bus_automated_score)[:composition]
    mutations=[->(s){s["version"]=6},->(s){s["automation"][1]["bus_id"]="foreign"},
      ->(s){s["automation"][1]["track_id"]="kick"},->(s){s["automation"][1]["track_id"]=nil},
      ->(s){s["automation"][1].delete("bus_id")},->(s){s["automation"][1]["parameter"]="cutoff"},
      ->(s){s["automation"][3]["parameter"]="pan"},->(s){s["automation"][3]["master"]=false},
      ->(s){s["automation"][3]["master"]="true"},->(s){s["automation"]<<s["automation"][1].deep_dup},
      ->(s){s["automation"][2]["enabled"]=false;s["automation"][2]["points"][0]["value"]=-1.01},
      ->(s){s["automation"][3]["points"][0]["value"]=1.51},->(s){s["bars"]=1}]
    mutations.each{|mutate|data=bus_automated_score;mutate.call(data);assert_raises(ArgumentError){save_score(data)}}
    assert_equal before,@scene.reload.settings["music"]
  end
  def test_bus_automation_uses_shared_budget_and_preserves_legacy_sources
    data=bus_automated_score
    data["tracks"]=(0...16).map{|i|data["tracks"][1].merge("id"=>"channel#{i}")}
    data["automation"]=data["tracks"].map{|t|{"track_id"=>t["id"],"parameter"=>"gain","points"=>(0...128).map{|i|{"beat"=>i/8.0,"value"=>0.5}}}}
    assert_equal 2048,save_score(data)[:composition]["automation"].sum{|l|l["points"].length}
    data["automation"]<<{"master"=>true,"parameter"=>"gain","points"=>[{"beat"=>0,"value"=>1}]}
    assert_raises(ArgumentError){save_score(data)}
    (1..6).each do |version|
      old=score.deep_stringify_keys.merge("version"=>version)
      old["automation"]=[{"track_id"=>"kick","parameter"=>"gain","points"=>[]}] if version>=3
      assert_equal version,save_score(old)[:composition]["version"]
    end
  end
end
