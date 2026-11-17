# Production source grants, ActiveStorage originals and resumable state machine;
# OAuth/YouTube and native-host transport are explicit external boundaries.
require_relative 'pwa_commercial_checks'
require File.join(ROOT,'db/migrate/20261117113000_create_pwa_youtube_uploads')
CreatePwaYoutubeUploads.new.migrate(:up)
%w[app/models/lightek_pwa/youtube_upload app/services/lightek_pwa/youtube_api app/services/lightek_pwa/youtube_publishing app/jobs/lightek_pwa/youtube_publish_job].each { |f| require File.join(ROOT,f) }

class PwaYoutubePublishingTest < PwaCommercialTest
  PwaCommercialTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    @before=ENV['LIGHTEK_YOUTUBE_UPLOADS_ENABLED']; ENV['LIGHTEK_YOUTUBE_UPLOADS_ENABLED']='true'
    @post=Post.create!(user:@owner,site:@site,kind:'video',title:'Original film',content:'Original video',visibility:'public',audience:'everyone')
    @post.media.attach(io:StringIO.new('actual-original-video'),filename:'original.mp4',content_type:'video/mp4',identify:false)
  end
  def teardown
    @before ? ENV['LIGHTEK_YOUTUBE_UPLOADS_ENABLED']=@before : ENV.delete('LIGHTEK_YOUTUBE_UPLOADS_ENABLED')
    super
  end
  def submit(**args)
    LightekPwa::YoutubePublishing.submit!(post:@post,actor:@owner,consent:true,made_for_kids:false,**args)
  end
  def response(code,body='',**headers)
    klass={'200'=>Net::HTTPOK,'201'=>Net::HTTPCreated,'308'=>Net::HTTPPermanentRedirect,'404'=>Net::HTTPNotFound,'503'=>Net::HTTPServiceUnavailable}.fetch(code)
    r=klass.new('1.1',code,'test');r.instance_variable_set(:@read,true);r.body=body;headers.each { |k,v| r[k.to_s]=v };r
  end
  def api(responses)
    calls=[]
    stub=Object.new
    stub.define_singleton_method(:channel!) { 'UC'+'a'*22 }
    stub.define_singleton_method(:request) { |method,url,**args| calls << [method,url,args]; raise IOError,'lost HTTP response' if responses.first==:timeout; responses.shift || raise('Unexpected request') }
    stub.define_singleton_method(:json!) { |r| raise LightekPwa::YoutubeApi::Unavailable unless r.is_a?(Net::HTTPSuccess);JSON.parse(r.body) }
    [stub,calls]
  end
  def session(upload)
    LightekVault::Service.store!(slug:upload.session_slug,payload:{'url'=>'https://www.googleapis.com/upload/youtube/v3/videos?upload_id=stable'})
  end
  def test_explicit_author_distribution_consent_and_kids_selection_are_required
    assert_raises(LightekPwa::YoutubePublishing::Unavailable) {submit(consent:false)}
    assert_raises(LightekPwa::YoutubePublishing::Unavailable) {submit(made_for_kids:nil)}
    assert_raises(LightekPwa::Policy::Denied) {submit(actor:@operator)}
    assert_empty LightekPwa::YoutubeUpload.all
  end
  def test_original_is_retained_and_submission_identity_is_stable
    upload=submit
    assert_equal upload.id,submit.id
    assert_equal @post.media.first.blob_id,upload.source_blob_id
    assert_equal @post.media.first.blob.checksum,upload.checksum
    assert @post.media.attached?
    assert_equal 'queued',upload.status
  end
  def test_source_grants_cannot_read_other_files_or_private_changed_posts
    upload=submit
    grant=LightekPwa::YoutubePublishing.verifier.generate({'upload_key'=>upload.public_key},purpose:'youtube-original',expires_in:1.hour)
    assert_equal upload.source_blob_id,LightekPwa::YoutubePublishing.source_blob!(grant).id
    assert_raises(LightekPwa::Policy::Denied) {LightekPwa::YoutubePublishing.source_blob!(grant+'bad')}
    @post.update!(visibility:'private')
    assert_raises(LightekPwa::YoutubePublishing::Unavailable) {LightekPwa::YoutubePublishing.source_blob!(grant)}
  end
  def test_durable_session_precedes_upload_bytes_and_processing_precedes_playback
    upload=submit
    stub,calls=api([response('200','',Location:'https://www.googleapis.com/upload/youtube/v3/videos?upload_id=stable'),response('308'),response('201',JSON.generate(id:'abcdefghijk'))])
    LightekPwa::YoutubePublishing.advance!(upload,api:stub)
    assert_equal 'processing',upload.reload.status
    assert_nil @post.reload.metadata['youtube_video_id']
    assert_equal 'https://www.googleapis.com/upload/youtube/v3/videos?upload_id=stable',LightekVault::Service.checkout!(slug:upload.session_slug)['url']
    assert_equal 'actual-original-video',calls.last[2][:body]
    assert_equal 'bytes 0-20/21',calls.last[2][:headers]['Content-Range']
    stub,calls=api([response('200',JSON.generate(items:[{id:'abcdefghijk',status:{uploadStatus:'processed',privacyStatus:'public',embeddable:true}}]))])
    LightekPwa::YoutubePublishing.advance!(upload,api:stub)
    assert_equal 'ready',upload.reload.status
    assert_equal 'abcdefghijk',@post.reload.metadata['youtube_video_id']
    assert @post.media.attached?
  end
  def test_lost_response_probes_the_same_session_instead_of_creating_another_upload
    upload=submit
    stub,calls=api([response('200','',Location:'https://www.googleapis.com/upload/youtube/v3/videos?upload_id=stable'),response('308'),:timeout])
    assert_raises(IOError) {LightekPwa::YoutubePublishing.advance!(upload,api:stub)}
    assert LightekVault::Secret.exists?(slug:upload.session_slug)
    stub,calls=api([response('200',JSON.generate(id:'abcdefghijk'))])
    LightekPwa::YoutubePublishing.advance!(upload,api:stub)
    assert_equal [:put],calls.map(&:first)
    assert_equal 'processing',upload.reload.status
  end
  def test_expired_session_requires_reconciliation_and_never_blind_reupload
    upload=submit;session(upload)
    stub,calls=api([response('404')])
    LightekPwa::YoutubePublishing.advance!(upload,api:stub)
    assert_equal 'reconciliation_required',upload.reload.status
    assert_equal 1,calls.size
    assert_nil @post.reload.metadata['youtube_video_id']
  end
  def test_google_credential_cannot_be_sent_to_redirect_or_untrusted_session_url
    upload=submit
    stub,calls=api([response('200','',Location:'https://evil.example/upload')])
    assert_raises(LightekPwa::YoutubeApi::Unavailable) {LightekPwa::YoutubePublishing.advance!(upload,api:stub)}
    assert_equal 1,calls.size
    refute LightekVault::Secret.exists?(slug:upload.session_slug)
    client=LightekPwa::YoutubeApi.allocate
    assert_raises(LightekPwa::YoutubeApi::Unavailable) {client.request(:put,'https://www.googleapis.com.evil.example/upload/youtube/v3/videos')}
  end
  def test_private_or_nonembeddable_video_never_becomes_pwa_youtube_playback
    upload=submit;upload.update!(status:'processing',video_id:'abcdefghijk')
    stub,calls=api([response('200',JSON.generate(items:[{id:'abcdefghijk',status:{uploadStatus:'processed',privacyStatus:'private',embeddable:true}}]))])
    LightekPwa::YoutubePublishing.advance!(upload,api:stub)
    assert_equal 'processing',upload.reload.status
    assert_nil @post.reload.metadata['youtube_video_id']
  end
  def test_withdrawal_is_not_overwritten_by_a_late_upload_receipt
    upload=submit
    LightekPwa::YoutubePublishing.request_withdrawal!(upload)
    LightekPwa::YoutubePublishing.uploaded!(upload,{'id'=>'abcdefghijk'})
    assert_equal 'withdraw_pending',upload.reload.status
    LightekPwa::YoutubePublishing.ready!(upload,'abcdefghijk')
    assert_equal 'withdraw_pending',upload.reload.status
    assert_nil @post.reload.metadata['youtube_video_id']
  end
  def test_confirmed_channel_deletion_preserves_the_members_original
    upload=submit;upload.update!(status:'ready',video_id:'abcdefghijk')
    LightekPwa::YoutubePublishing.request_withdrawal!(upload)
    r=Net::HTTPNoContent.new('1.1','204','test');r.instance_variable_set(:@read,true);r.body=''
    stub,calls=api([r])
    LightekPwa::YoutubePublishing.withdraw!(upload,api:stub)
    assert_equal 'withdrawn',upload.reload.status
    assert_equal :delete,calls.first.first
    assert @post.media.attached?
  end
  def test_deleting_source_post_keeps_a_durable_withdrawal_operation
    upload=submit
    @post.destroy!
    assert_nil upload.reload.post_id
    assert_equal 'withdraw_pending',upload.status
  end
  def test_historical_channel_receipt_preserves_earnings_attribution_after_post_removal
    upload=submit;upload.update!(status:'withdrawn',video_id:'abcdefghijk')
    @post.destroy!
    first=2.days.ago.to_date
    bytes="video_id,user_id,period_start,period_end,estimated_revenue_usd,creator_share_bps,views\nabcdefghijk,#{@owner.id},#{first},#{first},1.00,0,100\n"
    entry=LightekPwa::YoutubeImport.call(site:@site,actor:@operator,file:StringIO.new(bytes),source_reference:'Official historical channel report').sole
    assert_equal @owner.id,entry.user_id
    assert_equal 0,entry.creator_cents
    assert_equal 100,entry.amount_cents
  end
  def test_connected_source_refreshes_its_original_grant_and_uses_central_receipt
    @remote.update!(manifest:{'lightek_reservation_federation'=>{'origin'=>'https://lightek.test','credential_slug'=>'source-only'}})
    @post.update!(site:@remote)
    upload=submit
    assert_equal 'relaying',upload.status
    calls=[];transport=Object.new
    transport.define_singleton_method(:request) do |path,**args|
      calls << [path,args]
      {'key'=>'11111111-1111-4111-8111-111111111111','status'=>calls.size == 1 ? 'queued' : 'ready','video_id'=>'abcdefghijk'}
    end
    LightekReservations::Federation::Client.stub(:new,transport) {2.times {LightekPwa::YoutubePublishing.relay!(upload)}}
    assert_equal ['pwa/youtube','pwa/youtube'],calls.map(&:first)
    assert calls.all? { |_,args| args[:body][:source_grant].present? && !args[:body].key?(:refresh_token) }
    assert_equal 'ready',upload.reload.status
    assert_equal 'abcdefghijk',@post.reload.metadata['youtube_video_id']
  end
  def test_central_admission_binds_peer_creator_and_original_identity
    payload={'source_post_id'=>17,'source_grant'=>'opaque-grant','title'=>'Original','description'=>'Film','byte_size'=>21,
      'checksum'=>@post.media.first.blob.checksum,'content_type'=>'video/mp4','consent'=>true,'made_for_kids'=>false}
    upload=LightekPwa::YoutubePublishing.accept!(peer:@peer,payload:payload)
    assert_equal @owner.id,upload.user_id
    assert_equal @site.id,upload.site_id
    assert_equal upload.id,LightekPwa::YoutubePublishing.accept!(peer:@peer,payload:payload.merge('source_grant'=>'renewed')).id
    assert_raises(LightekPwa::YoutubePublishing::Unavailable) {LightekPwa::YoutubePublishing.accept!(peer:@peer,payload:payload.merge('checksum'=>'changed'))}
    @subscription.update!(status:'past_due')
    assert_raises(LightekPwa::Policy::Denied) {LightekPwa::YoutubePublishing.accept!(peer:@peer,payload:payload.merge('source_post_id'=>18))}
  end
  def test_resume_offsets_are_strict_and_bounded
    assert_equal 5,LightekPwa::YoutubePublishing.offset!(response('308','',Range:'bytes=0-4'),21)
    assert_raises(LightekPwa::YoutubeApi::Unavailable) {LightekPwa::YoutubePublishing.offset!(response('308','',Range:'bytes=5-10'),21)}
    assert_raises(LightekPwa::YoutubeApi::Unavailable) {LightekPwa::YoutubePublishing.offset!(response('308','',Range:'bytes=0-25'),21)}
  end
end
