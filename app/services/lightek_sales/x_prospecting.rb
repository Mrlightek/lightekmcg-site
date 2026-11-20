# frozen_string_literal: true

require 'base64'
require 'digest'
require 'net/http'
require 'securerandom'
require 'json'
require 'uri'

module LightekSales
  class XProspecting
    class Error < StandardError; end
    class Rejected < Error; end
    class Uncertain < Error; end

    API = 'https://api.x.com'
    WEB_HOSTS = %w[x.com www.x.com mobile.x.com twitter.com www.twitter.com mobile.twitter.com].freeze
    PURPOSE = 'social_prospecting'
    SCOPES = %w[tweet.read users.read dm.write offline.access].freeze
    OUTREACH_OUTCOMES = ['Message sent', 'Reply received', 'No response', 'Not a fit'].freeze
    CONSUMER = name

    def initialize(actor:, site:)
      @workspace = Workspace.new(actor: actor, site: site)
      @actor, @site = actor, @workspace.site
    end

    def account
      LightekVault::Secret.find_by(slug: slug, status: 'active')&.metadata
    end

    def connect!(token)
      manage_connection!
      save_account!(token.to_s.strip)
    end

    def start_oauth!(client_id:, client_secret:, callback_url:)
      manage_connection!
      client_id, client_secret = client_id.to_s.strip, client_secret.to_s.strip
      raise ArgumentError, 'Enter the X OAuth client ID and secret.' unless valid_credential?(client_id) && valid_credential?(client_secret)

      state = SecureRandom.urlsafe_base64(32)
      @site.with_lock do
        save_vault!(slug: app_slug, name: 'X OAuth app', payload: {'client_id' => client_id, 'client_secret' => client_secret},
          metadata: {'flow' => Digest::SHA256.hexdigest(state)})
      end
      verifier = SecureRandom.urlsafe_base64(48)
      uri = URI('https://x.com/i/oauth2/authorize')
      uri.query = URI.encode_www_form(response_type: 'code', client_id: client_id, redirect_uri: callback_url,
        scope: SCOPES.join(' '), state: state, code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
        code_challenge_method: 'S256')
      {url: uri.to_s, state: state, verifier: verifier, expires_at: 10.minutes.from_now.to_i}
    end

    def finish_oauth!(code:, state:, verifier:, callback_url:)
      manage_connection!
      raise ArgumentError, 'X did not return an authorization code.' unless valid_credential?(code)

      flow = Digest::SHA256.hexdigest(state)
      check_flow!(flow)
      app = checkout_vault!(app_slug)
      issued = exchange!(app, grant_type: 'authorization_code', code: code, code_verifier: verifier, redirect_uri: callback_url)
      save_account!(issued.fetch('access_token'), extra: issued.except('access_token').merge('oauth_client' => app), flow: flow)
    end

    def disconnect!
      manage_connection!
      @site.with_lock do
        [slug, app_slug].each do |key|
          next unless LightekVault::Secret.active.exists?(slug: key)

          LightekVault::Service.disable!(slug: key, requested_by: @actor.email_address)
        end
      end
    end

    def search(keywords)
      authorize!
      keywords = keywords.to_s.strip
      unless keywords.length.between?(2, 200) && !keywords.match?(/[[:cntrl:]]/)
        raise ArgumentError, 'Enter keywords or a phrase of 2–200 characters.'
      end

      credentials = checkout!
      response = request!(:get, '/2/tweets/search/recent', token: credentials.fetch('access_token'), query: {
        query: "(#{keywords}) -is:retweet", max_results: 20, expansions: 'author_id',
        'tweet.fields': 'created_at,author_id', 'user.fields': 'username,name,protected'
      })
      authors = response.dig('includes', 'users').to_a.index_by { |user| user['id'] }
      response['data'].to_a.filter_map do |post|
        author = authors[post['author_id']]
        next unless author && !author['protected'] && author['id'].to_s.match?(SocialProspect::X_ID) &&
          post['id'].to_s.match?(SocialProspect::X_ID) && author['id'] != credentials['account_id']

        ids = [@site.id, @actor.id, credentials['account_id'], author.fetch('id'), post.fetch('id')]
        {name: author['name'], username: author['username'], text: post['text'], post_id: post['id'],
          selection: verifier.generate(ids, expires_in: 20.minutes)}
      end
    end

    def save!(selection)
      authorize!
      site_id, actor_id, sender_id, remote_id, post_id = verifier.verify(selection.to_s)
      raise ActiveRecord::RecordNotFound unless site_id == @site.id && actor_id == @actor.id
      raise Error, 'The connected X account changed. Search again.' unless checkout!['account_id'] == sender_id

      SocialProspect.create_or_find_by!(site: @site, provider: 'x', remote_id: remote_id) do |prospect|
        prospect.assign_attributes(saved_by: @actor, sender_id: sender_id, source_post_id: post_id)
      end
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Error, 'This search result expired. Search again to save it.'
    end

    def save_web_post!(url)
      authorize!
      username, post_id = web_post_identity(url)
      raise ArgumentError, 'Paste the full X post link, including the author’s username and /status/.' unless username

      SocialProspect.create_or_find_by!(site: @site, provider: 'x', web_username: username) do |prospect|
        prospect.assign_attributes(saved_by: @actor, source_post_id: post_id)
      end
    end

    def send!(prospect, text:, permission:)
      authorize!
      raise Error, "Open the prospect’s profile to message them on #{prospect.provider_label}." if prospect.web_only?

      text, permission = text.to_s.strip, permission.to_s.strip
      raise ArgumentError, 'Write a message of 1–2000 characters.' unless text.length.between?(1, 2000)
      raise ArgumentError, 'Record how the person invited a DM to this account.' unless permission.length.between?(5, 250)

      credentials = checkout!
      raise Error, 'Reconnect the X account that saved this prospect.' unless prospect.sender_id == credentials['account_id']

      # Reserve before calling X. A timeout or process crash can leave an accepted
      # send without a receipt, so a second request must never replay it.
      prospect.with_lock do
        unless prospect.site_id == @site.id && prospect.outreach_status == 'ready' && !prospect.contact_blocked_at?
          raise Error, 'This prospect is unavailable for a new message.'
        end
        prospect.update!(outreach_status: 'sending', contact_permission: permission, contacted_by: @actor)
      end
      begin
        response = request!(:post, "/2/dm_conversations/with/#{prospect.remote_id}/messages", token: credentials.fetch('access_token'),
          body: {text: text})
        receipt = response['data']['dm_event_id'] if response['data'].is_a?(Hash)
        raise Uncertain, 'X returned no message receipt. Review the conversation in X.' unless receipt.to_s.match?(SocialProspect::X_ID)

        prospect.update!(outreach_status: 'sent', provider_message_id: receipt, contacted_at: Time.current)
      rescue Rejected
        prospect.update!(outreach_status: 'ready', contact_permission: nil, contacted_by: nil)
        raise
      rescue Error
        prospect.update!(outreach_status: 'uncertain')
        raise
      end
    end

    def record_outreach!(prospect, outcome:, notes:)
      authorize!
      raise ActiveRecord::RecordNotFound unless prospect.site_id == @site.id
      raise ArgumentError, 'Choose an outreach outcome.' unless OUTREACH_OUTCOMES.include?(outcome)
      notes = notes.to_s.strip
      raise ArgumentError, 'Keep the outreach note to 1000 characters.' if notes.length > 1000

      Activity.create!(site: @site, actor: @actor, record: prospect, kind: 'outreach',
        body: [outcome, notes.presence].compact.join("\n"))
    end

    def link_lead!(prospect, name:, email:, company:)
      authorize!
      @site.with_lock do
        prospect = SocialProspect.where(site: @site).lock.find(prospect.id)
        return prospect.lead if prospect.lead_id?
        raise Error, 'This prospect is marked Do not contact.' if prospect.contact_blocked_at?

        lead = Lead.find_by(site: @site, email: email.to_s.strip.downcase)
        lead ||= @workspace.save!('lead', {name: name, email: email, company: company.to_s.strip.presence || name,
          source: prospect.provider, next_step: "Follow up with the #{prospect.provider_label} prospect.", follow_up_on: Date.current + 1})
        prospect.update!(lead: lead)
        lead
      end
    end

    private

    def web_post_identity(url)
      url = url.to_s.strip
      return unless url.bytesize.between?(1, 2048)

      uri = URI.parse(url)
      return unless uri.is_a?(URI::HTTPS) && WEB_HOSTS.include?(uri.host&.downcase) && uri.port == 443 && uri.userinfo.nil?

      match = uri.path.match(%r{\A/([a-zA-Z0-9_]{1,15})/status/([0-9]{1,25})(?:/(?:photo|video)/[1-9][0-9]*)?/?\z})
      [match[1].downcase, match[2]] if match && !match[1].casecmp?('i')
    rescue URI::InvalidURIError
      nil
    end

    def slug = "lightek-x-prospecting-site-#{@site.id}"
    def app_slug = "#{slug}-oauth-app"

    def verifier = Rails.application.message_verifier(:lightek_x_search_selection)

    def authorize!
      @workspace.revalidate!
      LightekAgency::PackagePolicy.authorize!(@site.tenant, 'marketing')
      LightekAgency::PackagePolicy.authorize!(@site.tenant, 'commerce')
    end

    def manage_connection!
      authorize!
      raise ActiveRecord::RecordNotFound unless LightekAgency::Access.manage_members?(@actor, @site)
    end

    def valid_credential?(value)
      value.is_a?(String) && value.bytesize.between?(6, 4096) && value.ascii_only? && value.match?(/\A[!-~]+\z/)
    end

    def check_flow!(flow)
      app = LightekVault::Secret.active.find_by(slug: app_slug)
      raise Error, 'Start a new X sign-in from Prospecting.' unless app&.metadata&.fetch('flow', nil) == flow
    end

    def save_account!(token, extra: {}, flow: nil)
      raise ArgumentError, 'Enter an X user access token.' unless valid_credential?(token)
      identity = request!(:get, '/2/users/me', token: token).fetch('data', {})
      unless identity.is_a?(Hash) && identity['id'].to_s.match?(SocialProspect::X_ID) &&
        identity['username'].to_s.match?(/\A[a-zA-Z0-9_]{1,15}\z/)
        raise Error, 'X did not verify the connected account.'
      end

      @site.with_lock do
        check_flow!(flow) if flow
        save_vault!(slug: slug, name: 'X prospecting account', metadata: {'username' => identity['username']},
          payload: extra.merge('access_token' => token, 'account_id' => identity['id']))
      end
    end

    def save_vault!(slug:, name:, payload:, metadata: {})
      LightekVault::Service.store!(slug: slug, name: "#{name} / website #{@site.id}", payload: payload,
        provider: 'x', purpose: PURPOSE, access_policy: {'consumers' => [CONSUMER], 'purposes' => [PURPOSE]},
        metadata: metadata, requested_by: @actor.email_address)
    end

    def checkout_vault!(key)
      LightekVault::Service.checkout!(slug: key, consumer: CONSUMER, purpose: PURPOSE, requested_by: @actor.email_address)
    rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied
      raise Error, 'Connect or renew the X account before using prospecting.'
    end

    def checkout!
      credentials = checkout_vault!(slug)
      return credentials unless renewal_due?(credentials)

      @site.with_lock do
        credentials = checkout_vault!(slug)
        if renewal_due?(credentials)
          issued = exchange!(credentials.fetch('oauth_client'), grant_type: 'refresh_token', refresh_token: credentials.fetch('refresh_token'))
          credentials = credentials.merge(issued)
          save_vault!(slug: slug, name: 'X prospecting account', payload: credentials, metadata: account)
        end
        credentials
      end
    end

    def renewal_due?(credentials)
      credentials['expires_at'] && credentials['expires_at'].to_i <= 1.minute.from_now.to_i
    end

    def exchange!(app, **fields)
      data = request!(:post, '/2/oauth2/token', oauth_client: app, body: fields)
      access_token, refresh_token = data.values_at('access_token', 'refresh_token')
      expires_in = data['expires_in'].to_i
      unless valid_credential?(access_token) && valid_credential?(refresh_token) && expires_in.positive?
        raise Error, 'X did not return a renewable account token. Check the X app settings and reconnect.'
      end

      {'access_token' => access_token, 'refresh_token' => refresh_token, 'expires_at' => expires_in.seconds.from_now.to_i}
    end

    def request!(method, path, token: nil, query: {}, body: nil, oauth_client: nil)
      uri = URI("#{API}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      request = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri)
      request['Accept'] = 'application/json'
      if oauth_client
        request.basic_auth(oauth_client.fetch('client_id'), oauth_client.fetch('client_secret'))
        request.set_form_data(body)
      else
        request['Authorization'] = "Bearer #{token}"
        if body
          request['Content-Type'] = 'application/json'
          request.body = JSON.generate(body)
        end
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 8,
        write_timeout: 4, max_retries: 0) { |http| http.request(request) }
      case response.code.to_i
      when 200..299
        parsed = JSON.parse(response.body)
        return parsed if parsed.is_a?(Hash)
      when 400, 401, 402, 403, 404, 422, 429
        raise Rejected, rejection_message(response.code.to_i)
      end
      raise Uncertain, 'X did not confirm the request. Check the status on X before trying again.'
    rescue JSON::ParserError, IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
      raise Uncertain, 'X did not confirm the request. Check the status on X before trying again.'
    end

    def rejection_message(code)
      case code
      when 401, 403 then 'X denied access. Check account authorization, token scopes, and recipient permissions.'
      when 402 then 'X requires API credits for this request.'
      when 429 then 'X rate limited the account. Wait before trying again.'
      else 'X rejected the request. Check the search terms or the recipient on X.'
      end
    end
  end
end
