# frozen_string_literal: true
require_relative "studio_library_checks"
require File.join(ROOT,"app/services/studio/spatial/publication")
class SpatialPublicationTest < StudioLibraryTest
  StudioLibraryTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @access=Studio::PwaAccess.new("user_id"=>@alice.id,"site_id"=>@site.id)
    @asset=StudioAsset.create!(owner:@alice,site_id:@site.id,name:"Shared prop",kind:"glb",status:"ready",request_key:SecureRandom.uuid,metadata:{})
    blob=ActiveStorage::Blob.create_and_upload!(io:StringIO.new("glTF"),filename:"prop.glb",content_type:"model/gltf-binary")
    @asset.file.attach(blob);@asset.proxy.attach(blob)
    @object=@scene.scene_objects.create!(name:"Shared prop",object_type:"imported_asset",definition:{"asset_id"=>@asset.id,"location"=>[1,2,3],"rotation"=>[0,0,0],"scale"=>[1,1,1]})
    operation=@project.studio_operations.create!(studio_scene:@scene,operation_type:"build_scene",provider:"blender",capability:"studio.render.preview",status:"completed")
    artifact=operation.artifacts.create!(kind:"video",filename:"master.mp4");artifact.file.attach(io:StringIO.new("video"),filename:"master.mp4",content_type:"video/mp4")
    @publication=@project.studio_publications.create!(artifact:artifact,platform:"lightek_social",request_key:SecureRandom.uuid,status:"draft",metadata:{"user_id"=>@alice.id})
  end
  def capture(remix:true)
    Studio::Spatial::Publication.capture!(@publication,access:@access,scene:@scene,remix:remix,rights_confirmed:true)
    result=Studio::Publishers::LightekSocial.new(@publication).call
    Post.find(result.fetch("post_id"))
  end
  def test_published_snapshot_does_not_change_and_other_creator_can_fork_with_attribution
    post=capture
    @object.update!(definition:@object.definition.merge("location"=>[9,9,9]))
    manifest=Studio::Spatial::Publication.manifest(post)
    assert_equal [1,2,3],manifest[:scene][:objects].find { |o| o["id"]==@object.id }.dig("definition","location")
    assert_includes manifest[:scene][:objects].last["definition"]["asset_proxy_url"],"/posts/#{post.id}/spatial/assets/"
    access=Studio::PwaAccess.new("user_id"=>@bob.id,"site_id"=>@site.id)
    result=Studio::Spatial::Publication.fork!(post,access:access,request_key:"fork-test-123")
    assert_equal result,Studio::Spatial::Publication.fork!(post,access:access,request_key:"fork-test-123").merge(source_post_id:post.id)
    scene=StudioScene.find(result[:scene_id]);assert_equal @bob.id,scene.studio_project.owner_id
    assert_equal post.id,scene.settings["remix_source_post_id"]
    copy=scene.scene_objects.find_by(object_type:"imported_asset");refute_equal @asset.id,copy.definition["asset_id"]
    assert StudioAsset.find(copy.definition["asset_id"]).proxy.attached?
  end
  def test_hub_import_is_idempotent_and_view_only_posts_reject_forks
    post=capture;access=Studio::PwaAccess.new("user_id"=>@bob.id,"site_id"=>@site.id)
    first=Studio::Spatial::Publication.import_asset!(post,access:access,asset_id:@asset.id,request_key:"hub-import-123")
    assert_equal first.id,Studio::Spatial::Publication.import_asset!(post,access:access,asset_id:@asset.id,request_key:"hub-import-123").id
    assert_equal post.id,first.metadata["source"]["source_post_id"]
    post.update!(metadata:post.metadata.merge("spatial"=>post.metadata["spatial"].merge("allow_remix"=>false)))
    assert_raises(ArgumentError){Studio::Spatial::Publication.fork!(post,access:access,request_key:"forbidden-123")}
  end
  def test_spatial_http_uses_the_same_post_visibility_for_metadata_and_asset_bytes
    post=capture
    client=session_for(@bob)
    client.get "/api/lightek/pwa/posts/#{post.id}/spatial",headers:headers(@bob)
    assert_equal 200,client.response.status
    client.get "/api/lightek/pwa/posts/#{post.id}/spatial/assets/#{@asset.id}",headers:headers(@bob)
    assert_equal 200,client.response.status
    assert_equal "glTF",client.response.body
    post.update!(visibility:"private")
    client.get "/api/lightek/pwa/posts/#{post.id}/spatial",headers:headers(@bob)
    assert_equal 404,client.response.status
    client.get "/api/lightek/pwa/posts/#{post.id}/spatial/assets/#{@asset.id}",headers:headers(@bob)
    assert_equal 404,client.response.status
  end

end
