require_relative 'studio_director_finishing_checks'
%w[lightek_marketing/social_vault lightek_marketing/tiktok_video_upload studio/publishers/tik_tok studio/publishers/instagram].each { |name| require File.join(ROOT,"app/services/#{name}") }
require File.join(ROOT,'app/models/lightek_marketing/social_connection')
require File.join(ROOT,'app/jobs/studio_social_publication_poll_job')
ActiveRecord::Schema.define do
  create_table(:lightek_marketing_social_connections) do |t|
    t.references :site;t.string :provider,:account_label,:publish_endpoint,:credential_key;t.boolean :enabled,default:true;t.timestamps
  end unless table_exists?(:lightek_marketing_social_connections)
end
class StudioSocialTransportChecks < StudioDirectorFinishingChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def social_publication(platform,settings={})
    production=short_episode;artifact=Artifact.find(scene_exports(production).first)
    connection=LightekMarketing::SocialConnection.create!(site:@site,provider:platform,account_label:"#{platform}-#{SecureRandom.hex(4)}",publish_endpoint:'https://unused.example',credential_key:'fixture-only',enabled:true)
    publication=production.studio_project.studio_publications.create!(production:production,artifact:artifact,platform:platform,status:'draft',request_key:SecureRandom.uuid,metadata:{'user_id'=>@alice.id,'reviewed'=>true,'connection_id'=>connection.id,'title'=>'Reviewed episode','content'=>'A short scene','tiktok_settings'=>{'privacy_level'=>'SELF_ONLY','disable_comment'=>true,'disable_duet'=>true,'disable_stitch'=>true,'brand_content_toggle'=>false,'brand_organic_toggle'=>true,'is_aigc'=>true}.merge(settings)})
    [publication,connection]
  end
  def with_creds
    values={'access_token'=>'SECRET-NOT-IN-RECEIPTS','scope'=>'user.info.basic,video.publish','instagram_user_id'=>'12345'}
    LightekMarketing::SocialVault.stub(:checkout!,->(**_) { values }) { yield values }
  end
  def creator
    {'data'=>{'creator_nickname'=>'Creator','creator_username'=>'creator','privacy_level_options'=>['SELF_ONLY'],'comment_disabled'=>true,'duet_disabled'=>true,'stitch_disabled'=>true,'max_video_post_duration_sec'=>60},'error'=>{'code'=>'ok'}}
  end
  def test_tiktok_direct_post_uses_connected_credentials_and_waits_for_actual_confirmation
    publication,connection=social_publication('tiktok');calls=[]
    old=ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS'];ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS']=@site.host
    helpers=Rails.application.routes.url_helpers
    helpers.define_singleton_method(:rails_blob_url) { |attachment,host:,**_| "https://#{host}/media/#{attachment.blob.id}.mp4" }
    handler=->(uri,token,body={},**_) do
      calls << [uri.path,body];assert_equal 'SECRET-NOT-IN-RECEIPTS',token
      case uri.path
      when /creator_info/ then creator
      when /video\/init/ then {'data'=>{'publish_id'=>'remote-123'},'error'=>{'code'=>'ok'}}
      when /status\/fetch/ then {'data'=>{'status'=>'PUBLISH_COMPLETE','publicaly_available_post_id'=>['987']},'error'=>{'code'=>'ok'}}
      else raise uri.to_s
      end
    end
    with_creds do
      Studio::Publishers::TikTok.stub(:http!,handler) do
        StudioPublicationDispatchJob.perform_now(publication.id)
        assert_equal 'publishing',publication.reload.status
        assert_equal 'remote-123',publication.metadata.dig('social_submission','remote_id')
        assert_nil publication.published_at
        StudioSocialPublicationPollJob.perform_now(publication.id)
        assert_equal 'published',publication.reload.status
        StudioPublicationDispatchJob.perform_now(publication.id)
      end
    end
    assert_equal 1,calls.count { |path,_| path.include?('video/init') }
    refute_includes publication.reload.metadata.to_json,'SECRET'
    body=calls.find { |path,_| path.include?('video/init') }.last
    assert body.dig('post_info','is_aigc');assert_equal 'PULL_FROM_URL',body.dig('source_info','source')
  ensure
    ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS']=old
  end
  def test_tiktok_invalid_visibility_and_unknown_initial_response_do_not_create_duplicate_posts
    publication,connection=social_publication('tiktok',{'privacy_level'=>'PUBLIC_TO_EVERYONE'})
    with_creds do
      Studio::Publishers::TikTok.stub(:http!,->(*) { creator }) do
        assert_raises(ArgumentError) { StudioPublicationDispatchJob.perform_now(publication.id) }
      end
    end
    assert_equal 'failed',publication.reload.status
    assert_nil publication.metadata['social_submission']
    publication.update!(status:'draft',metadata:publication.metadata.merge('social_submission'=>{'phase'=>'requesting'}))
    with_creds { assert_raises(Studio::Publishers::SocialTransport::NeedsReview) { StudioPublicationDispatchJob.perform_now(publication.id) } }
    assert_equal 'needs_review',publication.reload.status
    StudioPublicationDispatchJob.perform_now(publication.id);assert_equal 'needs_review',publication.reload.status
  end
  def test_instagram_container_processing_is_not_publication_and_media_publish_runs_once
    publication,=social_publication('instagram');calls=[];status='IN_PROGRESS'
    helpers=Rails.application.routes.url_helpers;helpers.define_singleton_method(:rails_blob_url) { |attachment,host:,**_| "https://#{host}/media/#{attachment.blob.id}.mp4" }
    handler=->(uri,token,body={},method: :post) do
      calls << [uri.path,method,body]
      if uri.path.end_with?('/media_publish')
        {'id'=>'999'}
      elsif uri.path.end_with?('/media')
        assert_equal 'REELS',body['media_type'];{'id'=>'888'}
      else
        {'status_code'=>status}
      end
    end
    with_creds do
      Studio::Publishers::Instagram.stub(:http!,handler) do
        StudioPublicationDispatchJob.perform_now(publication.id);assert_equal 'publishing',publication.reload.status
        StudioSocialPublicationPollJob.perform_now(publication.id);assert_equal 'publishing',publication.reload.status
        status='FINISHED';StudioSocialPublicationPollJob.perform_now(publication.id)
        assert_equal 'published',publication.reload.status
        assert_equal '999',publication.metadata.dig('social_submission','media_id')
        StudioSocialPublicationPollJob.perform_now(publication.id)
      end
    end
    assert_equal 1,calls.count { |path,_,_| path.end_with?('/media_publish') }
  end
  def test_instagram_lost_publish_response_is_reconciled_without_a_second_publish_request
    publication,=social_publication('instagram')
    publication.update!(status:'publishing',metadata:publication.metadata.merge('social_submission'=>{'phase'=>'publishing_request','remote_id'=>'888'}))
    calls=0
    with_creds do
      Studio::Publishers::Instagram.stub(:http!,->(uri,*_,**_) { calls+=1;{'status_code'=>'FINISHED'} }) do
        StudioSocialPublicationPollJob.perform_now(publication.id)
      end
    end
    assert_equal 'needs_review',publication.reload.status
    assert_equal 1,calls
  end
  def test_tiktok_lost_initial_response_enters_reconciliation_instead_of_resubmitting
    publication,=social_publication('tiktok');old=ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS'];ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS']=@site.host
    Rails.application.routes.url_helpers.define_singleton_method(:rails_blob_url) { |attachment,host:,**_| "https://#{host}/media/#{attachment.blob.id}.mp4" }
    creates=0
    handler=->(uri,*_,**_) do
      if uri.path.include?('creator_info')
        creator
      else
        creates+=1;raise Net::ReadTimeout,'response lost'
      end
    end
    with_creds do
      Studio::Publishers::TikTok.stub(:http!,handler) do
        assert_raises(Studio::Publishers::SocialTransport::NeedsReview) { StudioPublicationDispatchJob.perform_now(publication.id) }
        StudioPublicationDispatchJob.perform_now(publication.id)
      end
    end
    assert_equal 1,creates
    assert_equal 'needs_review',publication.reload.status
    assert_equal 'needs_review',publication.metadata.dig('social_submission','phase')
  ensure
    ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS']=old
  end
  def test_social_connection_scope_and_disconnection_are_rechecked
    publication,connection=social_publication('instagram')
    connection.update!(site:@other_site)
    with_creds { assert_raises(ActiveRecord::RecordNotFound) { StudioPublicationDispatchJob.perform_now(publication.id) } }
    assert_equal 'failed',publication.reload.status
    assert_nil publication.metadata['social_submission']
    assert_raises(ArgumentError) { Studio::Publishers::SocialTransport.http!(URI('https://attacker.example/publish'),'secret') }
  end
end
