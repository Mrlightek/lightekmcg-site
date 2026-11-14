require_relative "studio_music_checks"
class StudioMusicScoringTest < StudioMusicTest
  StudioMusicTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def scoring_score
    score.merge(version:6,scoring:{start:4,cues:[{id:"door",name:"Door opens",time:6},{id:"intro",name:"Intro",time:4}]})
  end
  def test_scoring_save_bounds_and_independent_episode_cues
    saved=save_score(scoring_score)[:composition]
    assert_equal [4,6],saved["scoring"]["cues"].map{|c|c["time"]}
    template=action("template_save",project_id:@project.id,name:"Scored show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Scored episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal saved,copy.settings["music"]
    changed=copy.settings["music"].deep_dup;changed["scoring"]["cues"][0]["name"]="New intro"
    save_score(changed,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal "Intro",@scene.reload.settings.dig("music","scoring","cues",0,"name")
    [->(s){s[:version]=5},->(s){s[:scoring][:start]=-1},->(s){s[:scoring][:start]=599},->(s){s[:scoring][:cues][0][:time]=601},->(s){s[:scoring][:cues]<<s[:scoring][:cues][0].dup},->(s){s[:scoring]=nil}].each do |mutate|
      data=scoring_score;mutate.call(data);assert_raises(ArgumentError){save_score(data)}
    end
  end
  def test_scoring_places_at_configured_start_and_only_moves_existing_mix_when_start_changes
    asset=recording;saved=save_score(scoring_score)
    placed=action("music_place",scene_id:@scene.id,asset_id:asset.id,revision:saved[:revision],lock_version:@scene.reload.lock_version)
    assert_equal 4,placed[:timeline]["clips"].sole["start"]
    edit=placed[:timeline].deep_dup;edit["clips"][0].merge!("start"=>7,"gain"=>0.4)
    action("timeline_save",scene_id:@scene.id,lock_version:@scene.reload.lock_version,timeline:edit)
    saved=save_score(scoring_score)
    result=action("music_place",scene_id:@scene.id,asset_id:asset.id,revision:saved[:revision],lock_version:@scene.reload.lock_version)
    assert_equal 7,result[:timeline]["clips"].sole["start"]
    revised=scoring_score;revised[:scoring][:start]=10;saved=save_score(revised)
    result=action("music_place",scene_id:@scene.id,asset_id:asset.id,revision:saved[:revision],lock_version:@scene.reload.lock_version)
    assert_equal 10,result[:timeline]["clips"].sole["start"]
    assert_equal 0.4,result[:timeline]["clips"].sole["gain"]
    assert_equal 10,@scene.reload.settings.dig("music_mix","score_start")
  end
  def test_exact_media_references_are_actor_and_site_scoped_and_bounded
    a=recording
    foreign=StudioAsset.create!(owner:@bob,site:@other_site,name:"Other",kind:"audio",status:"ready",request_key:SecureRandom.uuid,metadata:{duration:1})
    result=action("assets_list",asset_ids:[a.id,foreign.id]);assert_equal [a.id],result[:assets].map{|asset|asset[:id]}
    assert_raises(ArgumentError){action("assets_list",asset_ids:Array.new(65,a.id))}
    assert_raises(ArgumentError){action("assets_list",asset_ids:[1.5])}
  end
end
