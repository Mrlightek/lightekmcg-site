require_relative "studio_music_checks"
require File.join(ROOT,"app/services/studio/live/production_preset")
require File.join(ROOT,"app/services/lightek_sessions/presentation")
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
    mutations=[->(p){p[:version]=4},->(p){p[:layout]="execute"},->(p){p[:layout]="library"},->(p){p[:volume]=Float::NAN},
      ->(p){p[:volume]=nil},->(p){p[:loop]="yes"},->(p){p[:camera]="script"},->(p){p[:stage_asset_id]=1.5},
      ->(p){p[:subject][:height]=0},->(p){p[:subject][:source]="webcam_url"},->(p){p[:stream_key]="secret"}]
    mutations.each{|m|bad=data.deep_dup;m.call(bad);assert_raises(ArgumentError){save_live(bad)}}
    assert_equal before,@scene.reload.settings["live_preset"]
    StudioAsset.find(data[:stage_asset_id]).update!(status:"failed")
    assert_raises(ArgumentError){live_setup.read(@scene.id)}
  end
  def test_show_presentation_v2_round_trips_and_template_episodes_keep_independent_style
    data=preset.merge(version:2,presentation:{layout:"split",title:"Lightek After Hours",subtitle:"The conversation",brand:"LIGHTEK",ticker:"Welcome",background:"#102030",accent:"#abcdef"})
    result=save_live(data);style=result[:preset]["presentation"]
    assert_equal "split",style["layout"]
    assert_equal "Lightek After Hours",style["title"]
    refute style.key?("participants");refute style.key?("featured")
    template=action("template_save",project_id:@project.id,name:"Styled show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Styled episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal style,copy.settings.dig("live_preset","presentation")
    changed=copy.settings["live_preset"].deep_dup;changed["presentation"]["title"]="Episode two"
    save_live(changed,scene:copy)
    assert_equal "Lightek After Hours",@scene.reload.settings.dig("live_preset","presentation","title")
    assert_equal "Episode two",copy.reload.settings.dig("live_preset","presentation","title")
  end
  def test_show_presentation_rejects_room_identity_fields_and_invalid_styles_without_writing
    legacy=save_live(preset)[:preset];assert_equal 1,legacy["version"];refute legacy.key?("presentation")
    data=preset.merge(version:2,presentation:{layout:"presenter",title:"Show"});save_live(data)
    before=@scene.reload.settings["live_preset"]
    mutations=[->(p){p[:version]=1},->(p){p[:presentation]=[]},->(p){p[:presentation]=nil},
      ->(p){p[:presentation][:featured]="user-1"},->(p){p[:presentation][:participants]={}},
      ->(p){p[:presentation][:layout]="execute"},->(p){p[:presentation][:accent]="url(https://example.test)"},
      ->(p){p[:presentation][:room_key]="private"}]
    mutations.each{|mutate|bad=data.deep_dup;mutate.call(bad);assert_raises(ArgumentError){save_live(bad)}}
    assert_equal before,@scene.reload.settings["live_preset"]
    data[:presentation]={title:"x"*200,ticker:"y"*400}
    style=save_live(data)[:preset]["presentation"]
    assert_equal 120,style["title"].length;assert_equal 300,style["ticker"].length
    assert_raises(ArgumentError){save_live(preset)}
  end

  def test_graphic_placement_v3_round_trip_independent_episode_and_downgrade_protection
    data=preset.merge(version:3,presentation:{title:"Lightek News"},overlay:{enabled:true,x:920,y:40,width:300,height:150,opacity:0.75,fit:"contain"})
    saved=save_live(data)[:preset];assert_equal 3,saved["version"];assert_equal 0.75,saved.dig("overlay","opacity")
    assert_equal "contain",live_setup.read(@scene.id).dig(:preset,"overlay","fit")
    template=action("template_save",project_id:@project.id,name:"Graphic show",request_key:SecureRandom.uuid)
    episode=action("template_use",project_id:template[:project_id],name:"Graphic episode",request_key:SecureRandom.uuid)
    copy=StudioScene.find(episode[:scene_id]);assert_equal saved,copy.settings["live_preset"]
    changed=saved.deep_dup;changed["overlay"]["enabled"]=false;changed["overlay"]["x"]=60;save_live(changed,scene:copy)
    assert @scene.reload.settings.dig("live_preset","overlay","enabled");assert_equal 920,@scene.settings.dig("live_preset","overlay","x")
    refute copy.reload.settings.dig("live_preset","overlay","enabled")
    [1,2].each { |version| assert_raises(ArgumentError) { save_live(saved.except("overlay").merge("version"=>version)) } }
    assert_equal saved,@scene.reload.settings["live_preset"]
  end
  def test_graphic_placement_validates_bounds_switches_fields_and_legacy_defaults_without_writes
    data=preset.merge(version:3,overlay:{enabled:true,x:0,y:0,width:300,height:150,opacity:1,fit:"contain"});save_live(data);before=@scene.reload.settings["live_preset"]
    mutations=[->(p){p[:version]=2},->(p){p[:overlay]=nil},->(p){p[:overlay]=[]},->(p){p[:overlay][:url]="http://example.test"},->(p){p[:overlay][:enabled]="false"},->(p){p[:overlay][:x]=1281},->(p){p[:overlay][:y]=Float::INFINITY},->(p){p[:overlay][:width]=0},->(p){p[:overlay][:height]=721},->(p){p[:overlay][:opacity]=-0.1},->(p){p[:overlay][:opacity]=nil},->(p){p[:overlay][:fit]="cover"}]
    mutations.each { |mutate| bad=data.deep_dup;mutate.call(bad);assert_raises(ArgumentError) { save_live(bad) } }
    assert_equal before,@scene.reload.settings["live_preset"]
    defaults=live_setup.normalize({"version"=>3,"layout"=>"camera"})["overlay"]
    assert_equal({"enabled"=>true,"fit"=>"stretch","x"=>0.0,"y"=>0.0,"width"=>1280.0,"height"=>720.0,"opacity"=>1.0},defaults)
    legacy=live_setup.normalize({"version"=>1,"layout"=>"camera"});refute legacy.key?("overlay")
  end

end
