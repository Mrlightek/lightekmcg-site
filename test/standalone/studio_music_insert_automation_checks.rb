require_relative "studio_music_bus_automation_checks"
class StudioMusicInsertAutomationTest < StudioMusicBusAutomationTest
  StudioMusicBusAutomationTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def insert_automated_score
    data=bus_automated_score;data["version"]=8
    data["automation"]<<{"track_id"=>"kick","effect_id"=>"channel_eq","parameter"=>"low","points"=>[{"beat"=>0,"value"=>-24},{"beat"=>16,"value"=>24}]}
    data["automation"]<<{"bus_id"=>"kick","effect_id"=>"glue","parameter"=>"threshold","points"=>[{"beat"=>0,"value"=>-60},{"beat"=>16,"value"=>0}]}
    data["automation"]<<{"master"=>true,"effect_id"=>"echo","parameter"=>"wet","points"=>[{"beat"=>0,"value"=>0},{"beat"=>16,"value"=>1}]}
    data
  end
  def test_insert_automation_preserves_all_owner_types_and_independent_episode
    saved=save_score(insert_automated_score)[:composition]
    assert_equal 8,saved["version"]
    assert_equal %w[channel_eq glue echo],saved["automation"].last(3).map{|l|l["effect_id"]}
    template=action("template_save",project_id:@project.id,name:"Effect show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Effect episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal saved,copy.settings["music"]
    changed=copy.settings["music"].deep_dup;changed["automation"].last["enabled"]=false
    save_score(changed,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal true,@scene.reload.settings["music"]["automation"].last["enabled"]
    assert_equal false,copy.reload.settings["music"]["automation"].last["enabled"]
  end
  def test_insert_automation_rejects_wrong_insert_owner_parameter_and_old_version_without_write
    before=save_score(insert_automated_score)[:composition]
    mutations=[->(s){s["version"]=7},->(s){s["automation"].last["effect_id"]="missing"},
      ->(s){s["automation"][4]["effect_id"]="echo"},->(s){s["automation"][4]["effect_id"]=nil},
      ->(s){s["automation"][4]["parameter"]="wet"},->(s){s["automation"][4]["points"][0]["value"]=-25},
      ->(s){s["automation"][5]["points"][0]["value"]=-61},->(s){s["automation"][6]["points"][0]["value"]=1.01},
      ->(s){s["automation"]<<s["automation"].last.deep_dup}]
    mutations.each{|mutate|data=insert_automated_score;mutate.call(data);assert_raises(ArgumentError){save_score(data)}}
    assert_equal before,@scene.reload.settings["music"]
  end
  def test_insert_automation_supports_only_schedulable_parameters_and_shared_budget
    data=insert_automated_score
    {"eq"=>%w[low mid high],"compressor"=>%w[threshold ratio attack release knee],"delay"=>%w[delayTime feedback wet],"distortion"=>%w[wet]}.each do |kind,params|
      data["mixer"]["master"]["effects"]=[{"id"=>"echo","kind"=>kind,"enabled"=>false,"params"=>{}}]
      data["automation"]=params.map do |key|
        low,high=Studio::Music::Mixer::EFFECTS[kind][key]
        {"master"=>true,"effect_id"=>"echo","parameter"=>key,"enabled"=>false,"points"=>[{"beat"=>0,"value"=>low},{"beat"=>16,"value"=>high}]}
      end
      assert_equal params,save_score(data)[:composition]["automation"].map{|l|l["parameter"]}
    end
    data["automation"][0]["parameter"]="distortion"
    assert_raises(ArgumentError){save_score(data)}
  end
end
