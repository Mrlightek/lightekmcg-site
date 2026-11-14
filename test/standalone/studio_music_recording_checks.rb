require_relative "studio_music_checks"
class StudioMusicRecordingTest < StudioMusicTest
  StudioMusicTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def take_score
    score.deep_stringify_keys.tap do |s|
      s["version"]=5;s["tracks"]<<{"id"=>"take","instrument"=>"recording","name"=>"Voice take","asset_id"=>recording.id,"sample_in"=>0.1,"sample_out"=>0.9,"notes"=>[{"beat"=>2,"length"=>0.8*s["tempo"]/60,"pitch"=>60,"velocity"=>1}]}
    end
  end
  def test_recordings_save_fixed_source_timing_mix_and_independent_episode_edits
    data=take_score;saved=save_score(data)[:composition]
    take=saved["tracks"].last
    assert_equal 5,saved["version"];assert_equal recording.id,take["asset_id"]
    assert_equal 2,take["notes"].sole["beat"];assert_equal 0.1,take["sample_in"]
    assert_equal [],take["effects"];assert_equal 60,take["root"]
    template=action("template_save",project_id:@project.id,name:"Recording show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Recording episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal saved,copy.settings["music"]
    changed=copy.settings["music"].deep_dup;changed["tracks"].last["notes"][0]["beat"]=4
    save_score(changed,scene_id:copy.id,lock_version:copy.lock_version)
    assert_equal 2,@scene.reload.settings.dig("music","tracks",2,"notes",0,"beat")
    assert_equal 4,copy.reload.settings.dig("music","tracks",2,"notes",0,"beat")
  end
  def test_recordings_validate_version_source_pitch_duration_pattern_boundaries_and_access
    save_score(take_score);before=@scene.reload.settings["music"]
    mutations=[->(s){s["version"]=4},->(s){s["tracks"].last["notes"]=[]},->(s){s["tracks"].last["notes"][0]["pitch"]=64},
      ->(s){s["tracks"].last["notes"][0]["length"]=1},->(s){s["tracks"].last["sample_out"]=2},
      ->(s){s["tracks"].last["notes"]<<s["tracks"].last["notes"][0].merge("beat"=>4)},
      ->(s){s["patterns"]=[{"id"=>"p","bars"=>1,"tracks"=>[{"track_id"=>"take","notes"=>s["tracks"].last["notes"]}]}]}]
    mutations.each{|mutate|data=take_score;mutate.call(data);assert_raises(ArgumentError){save_score(data)}}
    assert_equal before,@scene.reload.settings["music"]
    @alice.update!(role:"member");recording.update!(site:@other_site,owner:@bob)
    assert_raises(ActiveRecord::RecordNotFound){save_score(take_score)}
  end
  def test_long_recordings_support_more_than_sixty_four_beats_and_remain_bounded
    a=recording;a.update!(metadata:a.metadata.merge("duration"=>90))
    data=take_score;data["bars"]=64;take=data["tracks"].last;take["sample_in"]=0;take["sample_out"]=90;take["notes"][0]["length"]=150
    assert_equal 150,save_score(data)[:composition]["tracks"].last["notes"][0]["length"]
    a.update!(metadata:a.metadata.merge("duration"=>121))
    assert_raises(ArgumentError){save_score(data)}
  end
end
