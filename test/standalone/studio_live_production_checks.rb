require_relative "studio_music_checks"
require File.join(ROOT,"app/services/studio/live/production_preset")
class StudioLiveProductionTest < StudioMusicTest
  StudioMusicTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def live_setup
    Studio::Live::ProductionPreset.new(user:@alice,site:@site)
  end
  def live_asset(kind="glb",site:@site,owner:@alice)
    asset=StudioAsset.new(owner:owner,site:site,kind:kind,status:"ready",name:"Production #{kind}",request_key:SecureRandom.uuid)
    asset.file.attach(io:StringIO.new("fixture"),filename:"source.#{kind}",content_type:"application/octet-stream",identify:false)
    asset.proxy.attach(asset.file.blob);asset.save!;asset
  end
  def preset
    {version:1,layout:"stage",stage_asset_id:live_asset.id,overlay_asset_id:live_asset("image").id,volume:0.4,camera:"0",subject:{source:"session",x:2,height:4,key:false}}
  end
  def save_live(data=preset,scene:@scene,lock:scene.reload.lock_version)
    live_setup.save(scene.id,preset:data,lock_version:lock)
  end
  def test_live_setup_saves_with_scene_lock_preserves_authoring_and_copies_to_episode
    before=@scene.settings.deep_dup;result=save_live;stored=@scene.reload.settings["live_preset"]
    assert_equal "stage",stored["layout"];assert_equal "session",stored["subject"]["source"]
    assert_equal before["resolution_x"],@scene.settings["resolution_x"]
    assert_equal @scene.lock_version,result[:lock_version]
    assert_match %r{\A/dashboard/studio-broadcasting/assets/\d+/proxy\?site_id=#{@site.id}\z},result[:assets].first[:url]
    assert_raises(ArgumentError){save_live(stored,lock:result[:lock_version]-1)}
    template=action("template_save",project_id:@project.id,name:"Live show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Live episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal stored,copy.settings["live_preset"]
    save_live(stored.merge("volume"=>0.1),scene:copy)
    assert_equal 0.4,@scene.reload.settings["live_preset"]["volume"]
    assert_equal 0.1,copy.reload.settings["live_preset"]["volume"]
  end
  def test_live_setup_rejects_foreign_scene_assets_and_unentitled_actor
    foreign=StudioProject.create!(owner:@bob,site:@other_site,name:"Foreign").studio_scenes.first
    assert_raises(ActiveRecord::RecordNotFound){live_setup.read(foreign.id)}
    data=preset;data[:stage_asset_id]=live_asset(site:@other_site,owner:@bob).id
    assert_raises(ActiveRecord::RecordNotFound){save_live(data)}
    @alice.update!(role:"member")
    assert_raises(Gatekeeper::StudioLivePolicy::Denied){live_setup}
  end
  def test_live_setup_validates_numbers_switches_assets_and_layouts_without_writing
    data=preset;save_live(data);before=@scene.reload.settings["live_preset"]
    mutations=[->(p){p[:version]=2},->(p){p[:layout]="execute"},->(p){p[:layout]="library"},->(p){p[:volume]=Float::NAN},
      ->(p){p[:volume]=nil},->(p){p[:loop]="yes"},->(p){p[:camera]="script"},->(p){p[:stage_asset_id]=1.5},
      ->(p){p[:subject][:height]=0},->(p){p[:subject][:source]="webcam_url"},->(p){p[:stream_key]="secret"}]
    mutations.each{|m|bad=data.deep_dup;m.call(bad);assert_raises(ArgumentError){save_live(bad)}}
    assert_equal before,@scene.reload.settings["live_preset"]
    StudioAsset.find(data[:stage_asset_id]).update!(status:"failed")
    assert_raises(ArgumentError){live_setup.read(@scene.id)}
  end
end
