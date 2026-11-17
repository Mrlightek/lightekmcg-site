require 'digest'
require 'base64'
require 'tempfile'
require 'ipaddr'
module LightekPwa
  class YoutubePublishing
    class Unavailable < StandardError; end
    CHUNK = 4.megabytes
    def self.central_enabled?(site)
      Policy.platform_operator(site).present? && LaunchSettings.enabled?('youtube_uploads_enabled')
    end
    def self.capacity!(site)
      limit = Integer(ENV.fetch('LIGHTEK_YOUTUBE_DAILY_UPLOAD_LIMIT', '20'))
      raise Unavailable, 'Channel publishing capacity is not configured' unless (1..1000).cover?(limit)
      raise Unavailable, 'The channel’s daily upload allowance has been reached. Try again tomorrow.' if YoutubeUpload.where(site: site).where('created_at >= ?', 1.day.ago).count >= limit
    end
    def self.verifier = Rails.application.message_verifier('pwa-youtube-source-v1')
    def self.public_video!(post)
      raise Unavailable, 'Publish a public video with one original video file first' unless post.parent_id.nil? && post.community_id.nil? && %w[video clip].include?(post.kind) && post.visibility == 'public' && post.audience == 'everyone' && post.moderation_state == 'published' && (!post.expires_at || post.expires_at.future?)
      blobs = post.media.blobs.to_a
      raise Unavailable, 'Choose one original video file' unless blobs.one? && %w[video/mp4 video/webm video/quicktime].include?(blobs.first.content_type)
      blobs.first
    end
    def self.submit!(post:, actor:, consent:, made_for_kids:)
      raise Policy::Denied, 'Only the author can submit this video' unless post.user_id == actor.id
      Policy.new(user: actor, site: post.site).authorize!
      raise Unavailable, 'Confirm you own distribution rights and authorize public upload to the Lightek YouTube channel' unless consent == true && [true,false].include?(made_for_kids)
      blob = public_video!(post)
      relay = LightekReservations::Federation::Client.config(post.site).present?
      raise Unavailable, 'Central YouTube publishing is not open yet' unless relay || central_enabled?(post.site)
      upload = nil
      post.site.with_lock do
        post.reload
        blob = public_video!(post)
        upload = YoutubeUpload.find_by(post: post)
        if upload && (upload.source_blob_id != blob.id || upload.made_for_kids != made_for_kids)
          raise Unavailable, 'Original video or audience choice changed; create a new post for a new submission'
        end
        unless upload
          capacity!(post.site) unless relay
          raise Unavailable, 'Daily video publishing limit reached. Try again tomorrow.' if YoutubeUpload.where(user: actor).where('created_at >= ?', 1.day.ago).count >= 10
          upload = YoutubeUpload.create!(post: post, site: post.site, user: actor, source_blob_id: blob.id, source_post_id: post.id,
            title: post.title.to_s.first(100).presence || 'Lightek creator video', description: post.content.to_s.first(4800),
            status: relay ? 'relaying' : 'queued', made_for_kids: made_for_kids, consented_at: Time.current,
            byte_size: blob.byte_size, checksum: blob.checksum, content_type: blob.content_type)
        end
      end
      if !%w[withdraw_pending withdrawn].include?(upload.status) && post.metadata['youtube_upload_key'] != upload.public_key
        post.update!(metadata: post.metadata.merge('youtube_upload_key'=>upload.public_key))
      end
      YoutubePublishJob.perform_later(upload.id)
      upload
    end
    def self.accept!(peer:, payload:)
      owner = Publications.context(peer)
      raise Policy::Denied, 'This instance cannot publish to the channel' unless owner[:active] && central_enabled?(owner[:site])
      source_id = Integer(payload.fetch('source_post_id'))
      raise Unavailable, 'Invalid source post' unless source_id.positive?
      peer.with_lock do
        upload = YoutubeUpload.find_by(peer: peer, source_post_id: source_id)
        if upload
          raise Unavailable, 'Original video changed; publish it as a new post' unless upload.checksum == payload['checksum'] && upload.byte_size == Integer(payload['byte_size'])
          # Refresh a source grant after worker/host recovery without restarting an upload.
          upload.update!(source_grant: payload.fetch('source_grant'))
        else
          capacity!(owner[:site])
          raise Unavailable, 'Daily video publishing limit reached' if YoutubeUpload.where(user: owner[:user]).where('created_at >= ?', 1.day.ago).count >= 10
          raise Unavailable, 'A redistribution consent receipt is required' unless payload['consent'] == true && [true,false].include?(payload['made_for_kids']) && payload.fetch('source_grant').to_s.bytesize <= 4096
          upload = YoutubeUpload.create!(peer: peer, site: owner[:site], user: owner[:user], source_post_id: source_id,
            title: payload.fetch('title').to_s.first(100), description: payload['description'].to_s.first(5000),
            made_for_kids: payload['made_for_kids'], source_grant: payload.fetch('source_grant'), consented_at: Time.current,
            byte_size: payload.fetch('byte_size'), checksum: payload.fetch('checksum'), content_type: payload.fetch('content_type'))
        end
        YoutubePublishJob.perform_later(upload.id)
        upload
      end
    end
    def self.relay!(upload)
      blob = public_video!(upload.post)
      raise Unavailable, 'Original video changed; publish it as a new post' unless blob.id == upload.source_blob_id && blob.checksum == upload.checksum
      client = LightekReservations::Federation::Client.new(upload.site)
      # Renew the expiring original grant while polling so a delayed central
      # worker can recover without asking the member to resubmit the original.
      grant = verifier.generate({'upload_key' => upload.public_key}, purpose: 'youtube-original', expires_in: 24.hours)
      data = client.request('pwa/youtube', method: :post, body: {source_post_id: upload.post_id, title: upload.title, description: upload.description,
        byte_size: upload.byte_size, checksum: upload.checksum, content_type: upload.content_type, source_grant: grant, consent: true, made_for_kids: upload.made_for_kids})
      raise Unavailable, 'Central publication identity changed' if upload.central_key && upload.central_key != data.fetch('key')
      upload.update!(central_key: data.fetch('key')) unless upload.central_key
      if data['status'] == 'ready'
        raise Unavailable, 'Invalid YouTube video receipt' unless data['video_id'].to_s.match?(Youtube::ID)
        ready!(upload, data['video_id'])
      elsif %w[failed reconciliation_required withdrawn].include?(data['status'])
        upload.update!(status: data['status'], error_code: data['error_code'])
      end
    end
    def self.source_blob!(grant)
      data = verifier.verified(grant, purpose: 'youtube-original') or raise Policy::Denied, 'Video source grant expired'
      upload = YoutubeUpload.find_by!(public_key: data.fetch('upload_key'))
      blob = public_video!(upload.post)
      raise Policy::Denied, 'Original source is no longer authorized' unless blob.id == upload.source_blob_id && blob.checksum == upload.checksum && !%w[withdraw_pending withdrawn].include?(upload.status)
      blob
    end
    def self.stage_remote!(upload)
      return if upload.staged_original.attached?
      order = upload.peer.order
      node = if upload.peer.respond_to?(:member_backend_id) && upload.peer.member_backend_id && upload.peer.member_backend
        upload.peer.member_backend.current_node
      else
        order.gatekeeper_application_launch&.gatekeeper_node || ProvisioningRequest.find_by(id: order.provisioning_request_id)&.gatekeeper_node
      end
      address = node&.ip_address.to_s
      raise Unavailable, 'Original source host has no verified server address' if address.blank?
      IPAddr.new(address) # Pin the managed node address; never resolve a submitted host/URL.
      host = URI(Publications.context(upload.peer)[:origin]).host
      uri = URI::HTTPS.build(host: host, path: '/api/lightek/pwa/youtube/source', query: URI.encode_www_form(grant: upload.source_grant))
      Tempfile.create(['pwa-original-', '.video'], binmode: true) do |io|
        size = 0; digest = Digest::MD5.new
        http = Net::HTTP.new(host,443,nil); http.ipaddr = address; http.use_ssl = true; http.open_timeout = 5; http.read_timeout = 20
        Timeout.timeout(180) do
          http.start do
            http.request(Net::HTTP::Get.new(uri)) do |response|
              raise Unavailable, 'Original video is unavailable' unless response.is_a?(Net::HTTPOK)
              response.read_body do |chunk|
                size += chunk.bytesize
                raise Unavailable, 'Original video exceeds its declared size' if size > upload.byte_size
                digest.update(chunk); io.write(chunk)
              end
            end
          end
        end
        raise Unavailable, 'Original video checksum or size mismatch' unless size == upload.byte_size && Base64.strict_encode64(digest.digest) == upload.checksum
        io.rewind
        upload.staged_original.attach(io: io, filename: "#{upload.public_key}.video", content_type: upload.content_type, identify: false)
      end
    end
    def self.advance!(upload, api: nil)
      return withdraw!(upload, api: api) if upload.status == 'withdraw_pending'
      return relay!(upload) if upload.status == 'relaying'
      return if %w[ready failed reconciliation_required withdrawn].include?(upload.status)
      raise Unavailable, 'Central channel publishing is paused' unless central_enabled?(upload.site)
      client = api || YoutubeApi.new
      begin
        upload.reload
        return if %w[ready failed reconciliation_required withdrawn].include?(upload.status)
        client.channel!
        if upload.status == 'processing'
          data = client.json!(client.request(:get, "https://www.googleapis.com/youtube/v3/videos?part=status,processingDetails&id=#{upload.video_id}"))
          video = data.fetch('items').first
          raise Unavailable, 'Uploaded video receipt is not available yet' unless video && video['id'] == upload.video_id
          status = video.fetch('status')
          if %w[failed rejected deleted].include?(status['uploadStatus']) || %w[failed terminated].include?(video.dig('processingDetails','processingStatus'))
            upload.update!(status: 'failed', error_code: 'youtube_processing_rejected')
          elsif status['uploadStatus'] == 'processed' && status['privacyStatus'] == 'public' && status['embeddable'] == true
            ready!(upload, upload.video_id)
            upload.staged_original.purge_later if upload.staged_original.attached?
          else
            upload.update!(error_code: 'waiting_for_public_embeddable_video')
          end
          return
        end
        if upload.peer
          stage_remote!(upload)
          blob = upload.staged_original.blob
        else
          blob = public_video!(upload.post)
          raise Unavailable, 'Original video changed' unless blob.id == upload.source_blob_id && blob.checksum == upload.checksum
        end
        session = session_for!(upload, blob, client)
        return if upload.reload.status == 'withdraw_pending'
        # Always probe the durable session first, including after an uncertain PUT.
        response = client.request(:put, session, body: '', headers: {'Content-Length'=>'0','Content-Range'=>"bytes */#{upload.byte_size}"})
        if response.code.in?(%w[200 201])
          uploaded!(upload, client.json!(response))
          return
        end
        if response.code.in?(%w[404 410])
          upload.update!(status: 'reconciliation_required', error_code: 'upload_session_expired_do_not_restart')
          return
        end
        raise YoutubeApi::Unavailable, 'Upload state could not be confirmed' unless response.code == '308'
        offset = offset!(response, upload.byte_size)
        blob.open do |io|
          6.times do
            break if upload.reload.status == 'withdraw_pending'
            break if offset >= upload.byte_size
            io.seek(offset)
            bytes = io.read([CHUNK,upload.byte_size-offset].min)
            response = client.request(:put, session, body: bytes, headers: {'Content-Type'=>upload.content_type, 'Content-Length'=>bytes.bytesize.to_s,
              'Content-Range'=>"bytes #{offset}-#{offset+bytes.bytesize-1}/#{upload.byte_size}"})
            if response.code.in?(%w[200 201])
              uploaded!(upload, client.json!(response)); break
            end
            raise YoutubeApi::Unavailable, 'Upload receipt is uncertain; retry will probe the same session' unless response.code == '308'
            offset = offset!(response, upload.byte_size)
          end
        end
      end
    ensure
      client&.close unless api
    end
    def self.offset!(response, total)
      range = response['Range']
      return 0 if range.blank?
      raise YoutubeApi::Unavailable, 'Invalid upload offset' unless range.match?(/\Abytes=0-\d+\z/)
      offset = range.split('-').last.to_i + 1
      raise YoutubeApi::Unavailable, 'Invalid upload offset' unless offset <= total
      offset
    end
    def self.session_for!(upload, blob, client)
      secret = LightekVault::Secret.find_by(slug: upload.session_slug)
      return LightekVault::Service.checkout!(slug: upload.session_slug, consumer: YoutubeApi::CONSUMER, purpose: 'youtube_publishing', requested_by: 'pwa-youtube-worker').fetch('url') if secret
      raise Unavailable, 'Upload session receipt is missing; reconcile the channel before retrying' if upload.session_started_at
      metadata = {snippet: {title: upload.title, description: (upload.description.to_s.first(4800) + "\nLightek publication: #{upload.public_key}"), categoryId: '22'},
        status: {privacyStatus: 'public', embeddable: true, selfDeclaredMadeForKids: upload.made_for_kids}}
      response = client.request(:post, 'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status', body: JSON.generate(metadata),
        headers: {'Content-Type'=>'application/json; charset=UTF-8','X-Upload-Content-Length'=>blob.byte_size.to_s,'X-Upload-Content-Type'=>blob.content_type})
      raise YoutubeApi::Unavailable, 'Could not initialize video upload' unless response.is_a?(Net::HTTPSuccess)
      url = response['Location'].to_s
      uri = URI.parse(url)
      raise YoutubeApi::Unavailable, 'Invalid upload session destination' unless uri.is_a?(URI::HTTPS) && uri.host == 'www.googleapis.com' && uri.port == 443 && uri.path == '/upload/youtube/v3/videos' && !uri.userinfo && !uri.fragment
      LightekVault::Service.store!(name: 'PWA video upload session', slug: upload.session_slug, payload: {'url'=>url}, purpose: 'youtube_publishing',
        access_policy: {'consumers'=>[YoutubeApi::CONSUMER], 'purposes'=>['youtube_publishing']}, requested_by: 'pwa-youtube-worker')
      upload.with_lock { upload.update!(session_started_at: upload.session_started_at || Time.current, status: upload.withdraw_requested_at ? 'withdraw_pending' : 'uploading') unless upload.status == 'withdrawn' }
      url
    end
    def self.uploaded!(upload, data)
      raise YoutubeApi::Unavailable, 'Invalid completed upload receipt' unless data['id'].to_s.match?(Youtube::ID)
      upload.with_lock do
        upload.update!(video_id: data['id'], status: upload.withdraw_requested_at ? (upload.status == 'withdrawn' ? 'withdrawn' : 'withdraw_pending') : 'processing', error_code: nil)
      end
    end
    def self.request_withdrawal!(upload)
      return upload if %w[withdraw_pending withdrawn].include?(upload.status)
      upload.update!(status: 'withdraw_pending', withdraw_requested_at: upload.withdraw_requested_at || Time.current)
      if upload.post && upload.post.metadata['youtube_upload_key'] == upload.public_key
        upload.post.update_columns(metadata: upload.post.metadata.except('youtube_video_id', 'youtube_upload_key'))
      end
      YoutubePublishJob.perform_later(upload.id)
      upload
    end
    def self.withdraw!(upload, api: nil)
      if !upload.peer && LightekReservations::Federation::Client.config(upload.site)
        data = LightekReservations::Federation::Client.new(upload.site).request('pwa/youtube', method: :post,
          body: {withdraw: true, source_post_id: upload.source_post_id})
        upload.update!(status: 'withdrawn') if data['status'] == 'withdrawn'
        return
      end
      client = api || YoutubeApi.new
      if upload.video_id.blank? && LightekVault::Secret.exists?(slug: upload.session_slug)
        session = LightekVault::Service.checkout!(slug: upload.session_slug, consumer: YoutubeApi::CONSUMER, purpose: 'youtube_publishing', requested_by: 'pwa-youtube-withdrawal').fetch('url')
        response = client.request(:put, session, body: '', headers: {'Content-Length'=>'0','Content-Range'=>"bytes */#{upload.byte_size}"})
        if response.code.in?(%w[200 201])
          data = client.json!(response)
          raise YoutubeApi::Unavailable, 'Invalid completed upload receipt' unless data['id'].to_s.match?(Youtube::ID)
          upload.update!(video_id: data['id'])
        elsif response.code != '308'
          upload.update!(status: 'reconciliation_required', error_code: 'withdrawal_requires_channel_review')
          return
        end
      end
      if upload.video_id.present?
        response = client.request(:delete, "https://www.googleapis.com/youtube/v3/videos?id=#{upload.video_id}")
        raise YoutubeApi::Unavailable, 'Video deletion could not be confirmed' unless response.code.in?(%w[204 404])
      end
      upload.update!(status: 'withdrawn', error_code: nil)
      upload.staged_original.purge_later if upload.staged_original.attached?
    ensure
      client&.close unless api
    end
    def self.ready!(upload, video_id)
      apply = lambda do
        upload.with_lock do
          return if upload.withdraw_requested_at || %w[withdraw_pending withdrawn].include?(upload.status)
          public_video!(upload.post) if upload.post
          upload.update!(status: 'ready', video_id: video_id, error_code: nil)
          upload.post.update!(metadata: upload.post.metadata.merge('youtube_video_id'=>video_id, 'youtube_upload_key'=>upload.public_key)) if upload.post
        end
      end
      upload.post ? upload.post.with_lock { apply.call } : apply.call
    end
  end
end
