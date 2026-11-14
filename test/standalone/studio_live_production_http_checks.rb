require_relative "broadcast_control_checks"
require File.join(ROOT,"app/services/studio/live/production_preset")
Rails.application.routes.append do
  get "/dashboard/live/production",to:"dashboard/live_broadcasts#production"
  post "/dashboard/live/production",to:"dashboard/live_broadcasts#save_production"
end
class StudioLiveProductionHttpTest < BroadcastControlTest
  BroadcastControlTest.instance_methods(false).grep(/^test_/).each{|method|undef_method(method)}
  def test_live_production_routes_preserve_site_scope_lock_and_csrf
    project=StudioProject.create!(owner:@alice,site:@site,name:"Reusable live show")
    scene=project.studio_scenes.first
    client=session_for
    Studio::Live::Destination.stub(:configured?,false) do
      client.get "/dashboard/live",headers:headers.merge("Accept"=>"text/html"),params:{site_id:@site.id,scene_id:scene.id}
      assert_equal 200,client.response.status,client.response.body.first(1000)
      assert_includes client.response.body,"Reusable live show"
      assert_includes client.response.body,"data-production-setup"
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
end
