require_relative "broadcast_control_checks"
require File.join(ROOT,"app/services/studio/live/production_preset")
require File.join(ROOT,"app/services/lightek_sessions/presentation")
Rails.application.routes.append do
  get "/dashboard/live/production",to:"dashboard/live_broadcasts#production"
  post "/dashboard/live/production",to:"dashboard/live_broadcasts#save_production"
end
class StudioLiveProductionHttpTest < BroadcastControlTest
  BroadcastControlTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def test_prepared_package_is_private_and_prefills_the_host_workspace
    project = StudioProject.create!(owner: @alice, site: @site, name: 'CEO show')
    scene = project.studio_scenes.first
    Studio::Live::ProductionPreset.new(user: @alice, site: @site).save(scene.id,
      preset: { version: 1, layout: 'camera' }, lock_version: scene.lock_version)
    command = { 'kind' => 'live_show', 'site_id' => @site.id, 'values' => {
      'title' => 'CEO update', 'brief' => "Launch roadmap\nPrivate <cue>", 'scene_id' => scene.id, 'destination' => 'restream',
      'house_look' => 'cinema', 'subtitle' => 'Build in public'
    } }
    action = NevaehOsAction.create!(user: @alice, request_key: SecureRandom.uuid, status: 'pending', command: command)
    result = NevaehOs::LiveShow.prepare!(@alice, command, action.id)
    action.update!(status: 'completed', result: result)
    assert_equal %w[Open Close], result.fetch('cues').values_at(0, -1).pluck('label')
    assert_equal scene.reload.lock_version, result.fetch('scene_revision')
    assert_equal ['cinema', 'CEO update', 'Build in public'], result.fetch('look').values_at('frame', 'headline', 'subtitle')
    assert_raises(ArgumentError) do
      NevaehOs::LiveShow.prepare!(@alice, command.merge('values' => command['values'].merge('house_look' => 'unknown')), action.id)
    end
    assert_raises(ArgumentError) do
      NevaehOs::LiveShow.prepare!(@alice, command.merge('values' => { 'title' => 'Show', 'brief' => 'a', 'destination' => 'arbitrary' }), action.id)
    end

    client = session_for
    Studio::Live::Destination.stub(:configured?, false) do
      client.get result.fetch('host_path'), headers: headers.merge('Accept' => 'text/html')
      assert_equal 200, client.response.status
      assert_equal 'private, no-store', client.response.headers['Cache-Control']
      assert_includes client.response.body, 'Private &lt;cue&gt;'
      assert_includes client.response.body, 'The prepared destination is unavailable.'
      assert_includes client.response.body, 'data-host-freestyle'
      assert_includes client.response.body, 'data-prepared-frame="cinema"'
      assert_includes client.response.body, 'value="Build in public"'
      assert_includes client.response.body, "data-prepared-revision=\"#{scene.lock_version}\""
      client.get '/dashboard/live', headers: headers.merge('Accept' => 'text/html'), params: { site_id: @other_site.id, show_id: action.id }
      assert_equal 404, client.response.status
      assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::LiveShow.for_host!(@bob, @site, action.id) }
    end
  end

  def test_live_production_routes_preserve_site_scope_lock_and_csrf
    project=StudioProject.create!(owner:@alice,site:@site,name:"Reusable live show")
    scene=project.studio_scenes.first
    client=session_for
    Studio::Live::Destination.stub(:configured?,false) do
      client.get "/dashboard/live",headers:headers.merge("Accept"=>"text/html"),params:{site_id:@site.id,scene_id:scene.id}
      assert_equal 200,client.response.status,client.response.body.first(1000)
      assert_includes client.response.body,"Reusable live show"
      assert_includes client.response.body,"data-production-setup"
      assert_includes client.response.body,"data-overlay-controls"
      assert_includes client.response.body,"/lightek/live/overlay.js?v=1"
    end
    path="/dashboard/live/production?site_id=#{@site.id}"
    client.get path,headers:headers,params:{scene_id:scene.id}
    assert_equal 200,client.response.status
    assert_nil body(client)["preset"]
    assert_equal "private, no-store",client.response.headers["Cache-Control"]
    payload={scene_id:scene.id,lock_version:scene.lock_version,preset:{version:1,layout:"camera",volume:0.25,subject:{}}}
    client.post path,headers:headers,params:payload,as: :json
    assert_equal 422,client.response.status,"CSRF must remain enforced"
    Dashboard::LiveBroadcastsController.allow_forgery_protection=false
    client.post path,headers:headers,params:payload,as: :json
    assert_equal 200,client.response.status,client.response.body
    assert_equal "camera",body(client).dig("preset","layout")
    client.post path,headers:headers,params:payload,as: :json
    assert_equal 422,client.response.status
    assert_includes body(client)["error"],"changed"
    client.post path,headers:headers,params:{scene_id:scene.id,lock_version:scene.reload.lock_version,preset:[1]},as: :json
    assert_equal 422,client.response.status
    client.get path,headers:headers,params:{scene_id:StudioProject.create!(owner:@bob,site:@other_site,name:"Private").studio_scenes.first.id}
    assert_equal 404,client.response.status
    client.get path,headers:headers(@bob),params:{scene_id:scene.id}
    assert_equal 403,client.response.status
  ensure
    Dashboard::LiveBroadcastsController.allow_forgery_protection=true
  end
  def test_show_presentation_and_graphic_placement_v3_http_round_trip_excludes_room_identities
    project=StudioProject.create!(owner:@alice,site:@site,name:"Show branding")
    scene=project.studio_scenes.first;client=session_for;path="/dashboard/live/production?site_id=#{@site.id}"
    payload={scene_id:scene.id,lock_version:scene.lock_version,preset:{version:3,layout:"session",overlay:{enabled:true,x:900,y:30,width:320,height:160,opacity:0.8,fit:"contain"},presentation:{layout:"split",title:"Network show",brand:"LIGHTEK",accent:"#aabbcc"}}}
    Dashboard::LiveBroadcastsController.allow_forgery_protection=false
    client.post path,headers:headers,params:payload,as: :json
    assert_equal 200,client.response.status,client.response.body
    result=body(client);assert_equal "Network show",result.dig("preset","presentation","title")
    refute result["preset"]["presentation"].key?("participants")
    client.get path,headers:headers,params:{scene_id:scene.id}
    assert_equal 3,body(client).dig("preset","version")
    assert_equal 900,body(client).dig("preset","overlay","x")
    assert_equal 0.8,body(client).dig("preset","overlay","opacity")
    payload[:lock_version]=result["lock_version"];payload[:preset][:presentation][:participants]={"user-99"=>{name:"Other guest"}}
    client.post path,headers:headers,params:payload,as: :json
    assert_equal 422,client.response.status
    assert_equal "Network show",scene.reload.settings.dig("live_preset","presentation","title")
  ensure
    Dashboard::LiveBroadcastsController.allow_forgery_protection=true
  end

end
