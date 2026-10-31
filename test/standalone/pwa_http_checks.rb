# frozen_string_literal: true
# Exercises the real API controllers against the real database workers. Only
# host authentication and the private Dispatch queue are replaced at boundaries.
require_relative "community_checks"
require "action_dispatch/testing/integration"
require File.join(ROOT, "app/services/lightek_pwa/site_context")
require File.join(ROOT, "app/services/lightek_social/access_denied")
require File.join(ROOT, "app/services/susu/workers/pwa")
require File.join(ROOT, "app/models/concerns/susuable")
require File.join(ROOT, "app/models/concerns/susu_lifecycle")
require File.join(ROOT, "app/models/susu_group")
ActiveRecord::Schema.define do
  create_table(:pwa_http_work_items) { |t| t.json :args; t.json :result; t.string :status; t.text :error }
end
module DymondDispatch
  class WorkItem < ApplicationRecord
    self.table_name = "pwa_http_work_items"
    def done? = status == "done"
    def failed? = status == "failed"
    def finished? = done? || failed?
  end
end
class Nevaeh
  def self.handle(**attributes)
    action, arguments = attributes.fetch(:args)
    worker=attributes.fetch(:context).fetch("capability").start_with?("studio.workspace.") ? Studio::Workers::Workspace : LightekCommunity::Workers::Pwa
    result = worker.perform(action, arguments)
    item = DymondDispatch::WorkItem.create!(args: [action, arguments], result: result, status: "done")
    Struct.new(:work_item).new(item)
  end
end
class ApplicationController < ActionController::Base
  before_action :require_authentication
  def self.allow_unauthenticated_access(**options) = skip_before_action(:require_authentication, **options)
  def current_user = User.find_by(id: request.headers["X-Pwa-Test-User"])
  def authenticated? = !!current_user
  def require_authentication
    render json: { error: "Authentication required" }, status: :unauthorized unless authenticated?
  end
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end
end
require File.join(ROOT, "app/controllers/api/lightek_pwa_controller")
require File.join(ROOT, "app/controllers/api/nevaeh_controller")
require File.join(ROOT,"app/controllers/posts_controller")
require File.join(ROOT,"app/controllers/communities_controller")
class PwaTestCsrfController < ApplicationController
  protect_from_forgery with: :exception
  def show = render(json: { csrf_token: form_authenticity_token })
end
Rails.application.routes.append do
  resources :posts
  resources :communities
  get "/api/lightek/pwa/assets/:id/:flavor",to:"api/lightek_pwa#asset_file"
  get "/api/lightek/ott/catalog",to:"api/lightek_pwa#ott_catalog"
  get "/api/lightek/pwa/live/:post_id/index.m3u8",to:"api/lightek_pwa#live_playlist"
  get "/api/lightek/pwa/live/:post_id/segments/:name",to:"api/lightek_pwa#live_segment",constraints:{name:/segment-\d+\.ts/},format:false
  get "/api/lightek/pwa/posts/:post_id/media/:attachment_id", to: "api/lightek_pwa#media"
  get "/api/lightek/pwa/communities/:slug/cover", to: "api/lightek_pwa#cover"
  get "/api/lightek/pwa", to: "api/lightek_pwa#show"
  post "/api/lightek/pwa/uploads", to: "api/lightek_pwa#upload"
  post "/api/nevaeh/execute", to: "api/nevaeh#execute"
  get "/api/nevaeh/executions/:id", to: "api/nevaeh#execution"
  get "/test/csrf", to: "pwa_test_csrf#show"
end
Rails.application.reload_routes!
Rails.application.env_config["action_dispatch.show_exceptions"] = :none if ENV["PWA_HTTP_DEBUG"]

class PwaHttpIntegrationTest < LightekCommunityIntegrationTest
  LightekCommunityIntegrationTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def session_for(user = @alice)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host! "lightek.test"
    session.instance_variable_set(:@test_user, user)
    session
  end
  def headers(user = @alice) = { "X-Pwa-Test-User" => user.id.to_s, "Accept" => "application/json" }
  def body(session) = JSON.parse(session.response.body)

  def test_api_feed_is_public_but_writes_require_authentication
    post = publish
    client = session_for
    client.get "/api/lightek/pwa?view=feed", headers: { "Accept" => "application/json" }
    assert_equal 200, client.response.status
    assert_equal post[:id], body(client)["posts"].first["id"]
    client.post "/api/nevaeh/execute", params: { capability: "community.join", payload: {} }, as: :json
    assert_equal 401, client.response.status
  end

  def test_api_overrides_spoofed_actor_and_site_before_dispatch
    Api::NevaehController.allow_forgery_protection = false
    client = session_for
    client.post "/api/nevaeh/execute", headers: headers, params: {
      capability: "community.post.create", payload: { user_id: @bob.id, site_id: @other_site.id,
        content: "My real post", request_key: SecureRandom.uuid }
    }, as: :json
    assert_equal 200, client.response.status, client.response.body
    result = body(client)
    post = Post.find(result.dig("result", "post", "id"))
    assert_equal @alice.id, post.user_id
    assert_equal @site.id, post.site_id
    receipt_id = result["work_item_id"]
    client.get "/api/nevaeh/executions/#{receipt_id}", headers: headers
    assert_equal 200, client.response.status
    assert_equal "completed", body(client)["status"]
    assert_equal "private, no-store", client.response.headers["Cache-Control"]
    client.get "/api/nevaeh/executions/#{receipt_id}", headers: headers(@bob)
    assert_equal 404, client.response.status
    assert_equal 1, Post.count
  ensure
    Api::NevaehController.allow_forgery_protection = true
  end

  def test_csrf_is_enforced_for_authenticated_mutations
    Api::NevaehController.allow_forgery_protection = true
    client = session_for
    client.post "/api/nevaeh/execute", headers: headers, params: {
      capability: "community.post.create", payload: { content: "No token", request_key: SecureRandom.uuid }
    }, as: :json
    assert_equal 422, client.response.status
    assert_equal 0, Post.count
  end

  def test_authenticated_upload_stamps_actor_and_site_with_a_valid_csrf_token
    Api::LightekPwaController.allow_forgery_protection = true
    client = session_for
    client.get "/test/csrf", headers: headers
    assert_equal 200, client.response.status
    token = body(client).fetch("csrf_token")
    require "base64"
    file = Tempfile.new(["pwa-upload", ".png"])
    file.binmode
    file.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=="))
    file.flush
    upload = Rack::Test::UploadedFile.new(file.path, "image/png")
    client.post "/api/lightek/pwa/uploads", headers: headers.merge("X-CSRF-Token" => token), params: { file: upload }
    assert_equal 201, client.response.status, client.response.body
    blob = ActiveStorage::Blob.find_signed!(body(client).fetch("signed_id"))
    assert_equal @alice.id, blob.metadata["lightek_user_id"]
    assert_equal @site.id, blob.metadata["lightek_site_id"]
    assert_equal "image/png", blob.content_type
  ensure
    file&.close!
  end

  def test_gender_restricted_media_is_authorized_on_each_range_request
    @alice.profile.update!(community_gender:"woman")
    @bob.profile.update!(community_gender:"man")
    blob=ActiveStorage::Blob.create_and_upload!(io:StringIO.new("0123456789"),filename:"clip.mp4",content_type:"video/mp4",identify:false,
      metadata:{"lightek_user_id"=>@alice.id,"lightek_site_id"=>@site.id})
    post=publish(kind:"video",audience:"women",media_ids:[blob.signed_id])
    url=post[:media].first[:url]
    client=session_for
    client.get url,headers:headers(@bob).merge("Range"=>"bytes=0-3")
    assert_equal 404,client.response.status
    client.get url,headers:headers.merge("Range"=>"bytes=2-5")
    assert_equal 206,client.response.status
    assert_equal "2345",client.response.body
    assert_equal "bytes 2-5/10",client.response.headers["Content-Range"]
    @alice.profile.update!(community_gender:"unspecified")
    client.get url,headers:headers
    assert_equal 404,client.response.status
  end

  def test_live_catalog_playlist_and_segments_share_the_audience_policy
    @alice.profile.update!(community_gender:"woman")
    @bob.profile.update!(community_gender:"man")
    @alice.define_singleton_method(:can_access_feature?){|_|true}
    slug=perform("community_create",name:"The Nail Salon",audience:"women",request_key:SecureRandom.uuid)[:community][:slug]
    operation=Studio::Live::Sessions.create!(user:@alice,site:@site,destination:"lightek",title:"Ladies chatting",community_slug:slug)
    post=Post.find(operation.metadata["post_id"])
    assert_equal "lightek_streaming",post.distribution
    directory=Studio::Live::Encoder.hls_directory(operation.id)
    FileUtils.mkdir_p(directory)
    File.binwrite(directory.join("segment-000000.ts"),"test-segment")
    File.write(directory.join("index.m3u8"),"#EXTM3U\n#EXTINF:2,\nsegment-000000.ts\n")
    client=session_for
    client.get "/api/lightek/ott/catalog",headers:headers(@bob)
    assert_empty body(client)["items"]
    client.get "/api/lightek/pwa/live/#{post.id}/index.m3u8",headers:headers(@bob)
    assert_equal 404,client.response.status
    client.get "/api/lightek/pwa/live/#{post.id}/segments/segment-000000.ts",headers:headers(@bob)
    assert_equal 404,client.response.status
    client.get "/api/lightek/pwa/live/#{post.id}/index.m3u8",headers:headers
    assert_equal 200,client.response.status
    assert_includes client.response.body,"/api/lightek/pwa/live/#{post.id}/segments/segment-000000.ts"
    client.get "/api/lightek/pwa/live/#{post.id}/segments/segment-000000.ts",headers:headers
    assert_equal 200,client.response.status
    assert_equal "test-segment",client.response.body
    @alice.profile.update!(community_gender:"man")
    assert_raises(ActiveRecord::RecordNotFound){Studio::Live::Sessions.authorize_content!(operation,@alice)}
    client.get "/api/lightek/pwa/live/#{post.id}/index.m3u8",headers:headers
    assert_equal 404,client.response.status
  ensure
    FileUtils.rm_rf(directory) if directory
  end

  def test_unknown_hosts_and_private_posts_are_not_exposed
    private_post = publish(visibility: "private")
    client = session_for
    client.get "/api/lightek/pwa?view=post&id=#{private_post[:id]}", headers: headers(@bob)
    assert_equal 404, client.response.status
    client.host! "unregistered.test"
    client.get "/api/lightek/pwa?view=feed", headers: headers
    assert_equal 404, client.response.status
  end
  def test_asset_import_is_actor_scoped_idempotent_and_served_privately
    Api::NevaehController.allow_forgery_protection = false
    blob=ActiveStorage::Blob.create_and_upload!(io:StringIO.new("glTFtest"),filename:"prop.glb",content_type:"model/gltf-binary",identify:false,
      metadata:{"lightek_user_id"=>@alice.id,"lightek_site_id"=>@site.id,"studio_kind"=>"glb"})
    client=session_for
    request={capability:"studio.workspace.asset.import",payload:{signed_id:blob.signed_id,name:"Prop",request_key:SecureRandom.uuid,user_id:@bob.id,site_id:@other_site.id}}
    2.times do
      client.post "/api/nevaeh/execute",headers:headers,params:request,as: :json
      assert_equal 200,client.response.status,client.response.body
    end
    assert_equal 1,StudioAsset.count
    asset=StudioAsset.first
    assert_equal @alice.id,asset.owner_id
    assert_equal @site.id,asset.site_id
    url="/api/lightek/pwa/assets/#{asset.id}/original"
    client.get url,headers:headers(@bob)
    assert_equal 404,client.response.status
    client.get url,headers:headers
    assert_equal 200,client.response.status
    assert_equal "glTFtest",client.response.body
    assert_equal "private, no-store",client.response.headers["Cache-Control"]
    request[:payload][:request_key]=SecureRandom.uuid
    client.post "/api/nevaeh/execute",headers:headers(@bob),params:request,as: :json
    assert_equal 422,client.response.status
    assert_equal 1,StudioAsset.count
  ensure
    Api::NevaehController.allow_forgery_protection = true
  end

  def test_completed_receipt_cannot_reveal_a_post_after_audience_revocation
    Api::NevaehController.allow_forgery_protection = false
    @alice.profile.update!(community_gender:"woman")
    client=session_for
    client.post "/api/nevaeh/execute",headers:headers,params:{capability:"community.post.create",payload:{content:"Private discussion",audience:"women",request_key:SecureRandom.uuid}},as: :json
    assert_equal 200,client.response.status
    receipt=body(client).fetch("work_item_id")
    @alice.profile.update!(community_gender:"man")
    client.get "/api/nevaeh/executions/#{receipt}",headers:headers
    assert_equal 404,client.response.status
  ensure
    Api::NevaehController.allow_forgery_protection = true
  end

  def test_legacy_routes_cannot_bypass_audience_or_author_policy
    @alice.profile.update!(community_gender:"woman")
    @bob.profile.update!(community_gender:"man")
    slug=perform("community_create",name:"The Nail Salon",audience:"women",request_key:SecureRandom.uuid)[:community][:slug]
    community=Community.find_by!(slug:slug)
    post=publish(slug:slug)
    client=session_for
    ["/posts/#{post[:id]}.json","/communities/#{community.id}.json"].each do |path|
      client.get path,headers:headers(@bob)
      assert_equal 404,client.response.status
    end
    client.get "/posts.json",headers:headers(@bob)
    assert_empty body(client)
    client.get "/communities.json",headers:headers(@bob)
    assert_empty body(client)
    client.get "/posts/#{post[:id]}.json",headers:headers
    assert_equal post[:id],body(client)["id"]
    public_post=publish
    PostsController.allow_forgery_protection=false
    CommunitiesController.allow_forgery_protection=false
    client.patch "/posts/#{public_post[:id]}.json",headers:headers(@bob),params:{post:{content:"Stolen"}},as: :json
    assert_equal 403,client.response.status
    client.post "/posts.json",headers:headers(@bob),params:{post:{user_id:@alice.id,content:"My post"}},as: :json
    assert_equal 201,client.response.status
    assert_equal @bob.id,Post.find(body(client)["id"]).user_id
    client.patch "/communities/#{community.id}.json",headers:headers(@bob),params:{community:{audience:"everyone"}},as: :json
    assert_equal 404,client.response.status
  ensure
    PostsController.allow_forgery_protection=true
    CommunitiesController.allow_forgery_protection=true
  end

end
