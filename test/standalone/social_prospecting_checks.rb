# Real CRM, prospect, Vault and Dashboard code with X HTTP as the test boundary.
require_relative 'growth_foundation_checks'
require 'minitest/mock'

vault_migration = ROOT.join('db/migrate/20260927111553_create_lightek_vault.rb').read
eval(vault_migration.gsub(', using: :gin', ''), TOPLEVEL_BINDING)
CreateLightekVault.new.migrate(:up)
require ROOT.join('db/migrate/20261120120000_create_lightek_sales_social_prospects')
CreateLightekSalesSocialProspects.new.migrate(:up)
require ROOT.join('db/migrate/20261120120100_add_web_identity_to_sales_social_prospects')
AddWebIdentityToSalesSocialProspects.new.migrate(:up)
require ROOT.join('db/migrate/20261120120200_add_prospecting_web_sources_and_cadences')
AddProspectingWebSourcesAndCadences.new.migrate(:up)
require ROOT.join('db/migrate/20261120120300_add_google_maps_business_prospect_fields')
AddGoogleMapsBusinessProspectFields.new.migrate(:up)

%w[secret audit_event].each { |name| require ROOT.join("app/models/lightek_vault/#{name}") }
%w[master_key crypto policy service].each { |name| require ROOT.join("app/services/lightek_vault/#{name}") }
require ROOT.join('app/models/lightek_sales/social_prospect')
require ROOT.join('app/models/lightek_sales/prospecting_cadence')
require ROOT.join('app/services/lightek_sales/x_prospecting')
require ROOT.join('app/services/lightek_sales/web_prospecting')
require ROOT.join('app/services/lightek_sales/prospecting_cadences')
require ROOT.join('app/controllers/dashboard/sales_prospecting_controller')
Dashboard::SalesProspectingController.prepend_view_path ROOT.join('app/views')
Dashboard::SalesProspectingController.layout false

class SocialProspectingChecks < GrowthFoundationChecks
  def self.runnable_methods = instance_methods.grep(/^test_prospecting_/).map(&:to_s)

  TOKEN = 'test-x-user-token-checkout'

  def setup
    LightekSales::ProspectingCadence.delete_all
    LightekSales::SocialProspect.delete_all
    LightekVault::AuditEvent.delete_all
    LightekVault::Secret.delete_all
    super
    @prospecting = LightekSales::XProspecting.new(actor: @owner, site: @site)
    @calls = []
  end

  def x_http(status: 201)
    handler = Object.new
    handler.define_singleton_method(:request) do |request|
      yield(request, status)
    end
    ->(host, port, **options, &block) do
      assert_equal 'api.x.com', host
      assert_equal 443, port
      assert_equal true, options[:use_ssl]
      assert_equal 0, options[:max_retries]
      block.call(handler)
    end
  end

  def provider_response(request, message_status)
    @calls << request
    if request.path == '/2/oauth2/token'
      assert_equal 'POST', request.method
      assert_equal "Basic #{Base64.strict_encode64('test-client-id:test-client-secret')}", request['Authorization']
      fields = URI.decode_www_form(request.body).to_h
      if fields['grant_type'] == 'authorization_code'
        assert_equal 'fixture-oauth-code', fields['code']
        assert_equal @oauth_challenge, Base64.urlsafe_encode64(Digest::SHA256.digest(fields.fetch('code_verifier')), padding: false)
        assert_equal @oauth_callback_url, fields['redirect_uri']
      else
        assert_equal 'refresh_token', fields['grant_type']
        assert_equal 'test-first-refresh-token', fields['refresh_token']
      end
      return OpenStruct.new(code: '200', body: JSON.generate(access_token: TOKEN,
        refresh_token: fields['grant_type'] == 'refresh_token' ? 'test-rotated-refresh-token' : 'test-first-refresh-token',
        expires_in: 7200))
    end
    assert_equal "Bearer #{TOKEN}", request['Authorization']
    if request.path == '/2/users/me'
      payload = {'data' => {'id' => '900', 'username' => 'AgencyAccount'}}
    elsif request.path.start_with?('/2/tweets/search/recent?')
      assert_equal '("need a web designer") -is:retweet', URI.decode_www_form(URI.parse(request.path).query).to_h['query']
      payload = {'data' => [{'id' => '200', 'author_id' => '100', 'text' => 'Looking for a web designer, DM me.'}],
        'includes' => {'users' => [{'id' => '100', 'name' => 'Taylor', 'username' => 'TaylorWorks'}]}}
    else
      assert_equal '/2/dm_conversations/with/100/messages', request.path
      assert_equal 'POST', request.method
      assert_equal 'I saw your invitation to discuss website design.', JSON.parse(request.body)['text']
      raise Net::ReadTimeout if message_status == :timeout

      return OpenStruct.new(code: message_status.to_s, body: JSON.generate(data: {dm_event_id: '300'}))
    end
    OpenStruct.new(code: '200', body: JSON.generate(payload))
  end

  def with_provider(status: 201, &block)
    key = Base64.strict_encode64('p' * 32)
    LightekVault::MasterKey.stub(:resolve!, key) do
      Net::HTTP.stub(:start, x_http(status: status) { |request, code| provider_response(request, code) }, &block)
    end
  end

  def capture_http
    domain = {site_id: @site.id}
    post connect_dashboard_sales_prospecting_path(**domain),
      params: {authenticity_token: token, x_access_token: TOKEN}, headers: headers
    assert_response :see_other
    secret = LightekVault::Secret.find_by!(slug: "lightek-x-prospecting-site-#{@site.id}")
    assert_equal 'AgencyAccount', secret.metadata.fetch('username')
    refute_includes secret.attributes.to_s, TOKEN
    post search_dashboard_sales_prospecting_path(**domain), params: {authenticity_token: token, keywords: '"need a web designer"'}, headers: headers
    assert_response :success
    assert_includes response.body, 'TaylorWorks'
    assert_includes response.body, 'Looking for a web designer'
    selection = Nokogiri::HTML(response.body).at_css('input[name="selection"]')['value']
    assert_no_match(/#{TOKEN}/, response.body)
    2.times do
      post save_dashboard_sales_prospecting_path(**domain), params: {authenticity_token: token, selection: selection}, headers: headers
      assert_response :see_other
    end
    assert_equal 1, LightekSales::SocialProspect.count
    assert_nil LightekSales::SocialProspect.last.lead
    assert_equal 0, LightekSales::Lead.count
    LightekSales::SocialProspect.last
  end

  def message_http(prospect, confirmed: '1')
    post message_dashboard_sales_prospect_path(prospect, site_id: @site.id),
      params: {authenticity_token: token, confirmed: confirmed, contact_permission: 'The source post invited this account to send a DM.',
        outreach_text: 'I saw your invitation to discuss website design.'}, headers: headers
  end

  def test_prospecting_saves_web_post_links_without_x_credentials
    save_path = save_web_dashboard_sales_prospecting_path(site_id: @site.id)
    prospects = LightekSales::SocialProspect.where(site: @site)
    Net::HTTP.stub(:start, ->(*) { flunk 'Saving a web post must not call X' }) do
      [
        'https://x.com.evil.example/TaylorWorks/status/123',
        'https://x.com/i/web/status/123',
        'https://user:pass@x.com/TaylorWorks/status/123'
      ].each do |url|
        post save_path, params: {authenticity_token: token, post_url: url}, headers: headers
        assert_response :see_other
      end
      assert_empty prospects

      post save_path, params: {authenticity_token: token, post_url: 'https://x.com/TaylorWorks/status/123?s=20'}, headers: headers
      assert_redirected_to dashboard_sales_prospecting_path(site_id: @site.id)
      prospect = prospects.sole
      assert_equal @owner, prospect.saved_by
      assert_nil prospect.sender_id
      assert_nil prospect.remote_id
      assert_equal 'https://x.com/taylorworks/status/123', prospect.source_url
      assert_equal 'https://x.com/taylorworks', prospect.profile_url

      get dashboard_sales_prospecting_path(site_id: @site.id), headers: headers
      assert_response :success
      page = Nokogiri::HTML(response.body)
      assert_equal save_path, page.at_css('form:has(input[name="post_url"])')['action']
      assert_equal prospect.profile_url, page.at_css('details [data-prospect-draft] a')['href']

      message_http(prospect)
      assert_response :see_other
      assert_equal 'ready', prospect.reload.outreach_status
      post block_contact_dashboard_sales_prospect_path(prospect, site_id: @site.id),
        params: {authenticity_token: token}, headers: headers
      assert prospect.reload.contact_blocked_at?
      post save_path, params: {authenticity_token: token, post_url: 'https://twitter.com/TAYLORWORKS/status/456/photo/1'}, headers: headers
      assert_equal prospect, prospects.sole
      assert prospect.reload.contact_blocked_at?
      assert_equal '123', prospect.source_post_id
      assert_empty LightekVault::Secret.all
    end
  end

  def test_prospecting_oauth_verifies_state_and_refreshes_the_vault_connection
    with_provider do
      https!
      options = {site_id: @site.id}
      2.times do |attempt|
        post authorize_x_dashboard_sales_prospecting_path(**options), params: {authenticity_token: token,
          x_client_id: 'test-client-id', x_client_secret: 'test-client-secret'}, headers: headers
        assert_response :see_other
        authorize_uri = URI(response.location)
        assert_equal 'x.com', authorize_uri.host
        oauth = URI.decode_www_form(authorize_uri.query).to_h
        assert_equal 'S256', oauth['code_challenge_method']
        assert_includes oauth['scope'].split, 'offline.access'
        assert_not_includes authorize_uri.to_s, 'test-client-secret'
        @oauth_challenge = oauth.fetch('code_challenge')
        @oauth_callback_url = oauth.fetch('redirect_uri')
        callback_state = attempt.zero? ? 'wrong-state' : oauth.fetch('state')
        get x_callback_dashboard_sales_prospecting_path, params: {state: callback_state, code: 'fixture-oauth-code'}, headers: headers
        assert_response :see_other
        assert_equal attempt, @calls.count { |request| request.path == '/2/oauth2/token' }
      end
      assert_equal 'AgencyAccount', @prospecting.account.fetch('username')

      travel 3.hours do
        results = @prospecting.search('"need a web designer"')
        assert_equal 'TaylorWorks', results.first.fetch(:username)
        assert_equal 2, @calls.count { |request| request.path == '/2/oauth2/token' }
        @prospecting.search('"need a web designer"')
        assert_equal 2, @calls.count { |request| request.path == '/2/oauth2/token' }
      end
    end
  end

  def test_prospecting_saves_facebook_linkedin_and_reddit_without_api_requests
    examples = {
      'facebook' => ['https://m.facebook.com/share/p/PfBID123/?tracking=test', 'https://facebook.com/people/Taylor-Works/123/',
        'https://www.facebook.com/profile.php?id=123'],
      'linkedin' => ['https://www.linkedin.com/feed/update/urn:li:activity:1234/?trk=test', 'https://linkedin.com/in/Taylor-Works/',
        'https://www.linkedin.com/in/taylor-works'],
      'reddit' => ['https://www.reddit.com/r/smallbusiness/s/abc123?share_id=test', 'https://old.reddit.com/u/TaylorWorks/?x=y',
        'https://www.reddit.com/user/taylorworks']
    }
    save_path = save_web_dashboard_sales_prospecting_path(site_id: @site.id)

    Net::HTTP.stub(:start, ->(*) { flunk 'Browser handoffs must not use provider APIs' }) do
      examples.each do |provider, (post_url, profile_url, canonical)|
        2.times do
          post save_path, params: {provider: provider, post_url: post_url, profile_url: profile_url,
            display_name: 'Taylor Works', authenticity_token: token}, headers: headers
          assert_response :see_other
        end
        prospect = LightekSales::SocialProspect.where(site: @site, provider: provider).sole
        assert_equal canonical, prospect.profile_url
        assert_equal 'Taylor Works', prospect.name
        refute_includes prospect.source_url, 'test'
        get dashboard_sales_prospecting_path(site_id: @site.id, prospect_id: prospect.id), headers: headers
        assert_response :success
        page = Nokogiri::HTML(response.body)
        assert_equal canonical, page.at_css('[data-prospect-draft] a')['href']
        assert_includes response.body, "Search on #{prospect.provider_label}"
        message_http(prospect)
        assert_equal 'ready', prospect.reload.outreach_status
      end
    end

    web = LightekSales::WebProspecting.new(actor: @owner, site: @site)
    assert_raises(ArgumentError) do
      web.save!(provider: 'linkedin', post_url: examples.fetch('linkedin')[0],
        profile_url: 'https://www.linkedin.com/in/%2e%2e', name: 'Bad link')
    end
    assert_raises(ArgumentError) do
      web.save!(provider: 'facebook', post_url: 'https://facebook.com.evil.example/a/posts/123',
        profile_url: examples.fetch('facebook')[1], name: 'Bad link')
    end
    linkedin = LightekSales::SocialProspect.find_by!(site: @site, provider: 'linkedin')
    lead = @prospecting.link_lead!(linkedin, name: 'Taylor Works', email: 'linkedin@example.test', company: 'Taylor Works')
    assert_equal 'linkedin', lead.source
  end

  def test_prospecting_cadence_schedules_once_and_prioritizes_logged_replies
    prospect = @prospecting.save_web_post!('https://x.com/TaylorWorks/status/123')
    other = @prospecting.save_web_post!('https://x.com/OtherProspect/status/456')
    start = 1.day.ago.change(sec: 0)
    today_path = dashboard_sales_path(site_id: @site.id, owner_id: @member.id)
    post cadences_dashboard_sales_prospecting_path(site_id: @site.id),
      params: {authenticity_token: token, cadence: {name: 'Founder interest',
        steps: [{days: 0, title: 'Review reply'}, {days: 2, title: 'Close the loop'}]}},
      headers: headers
    cadence = LightekSales::ProspectingCadence.where(site: @site).sole
    focused_path = dashboard_sales_prospecting_path(site_id: @site.id, prospect_id: prospect.id)
    get focused_path, headers: headers
    assert_includes response.body, 'Apply a cadence'

    options = {cadence_id: cadence.id, owner_id: @member.id, starts_at: start.iso8601}
    2.times do
      post cadence_dashboard_sales_prospect_path(prospect, site_id: @site.id),
        params: {authenticity_token: token, cadence: options}, headers: headers
      assert_redirected_to focused_path
    end
    tasks = LightekSales::Task.where(record: prospect).order(:due_at)
    assert_equal ['Review reply', 'Close the loop'], tasks.pluck(:title)
    assert_equal [start, start + 2.days], tasks.pluck(:due_at)
    assert_equal [@member.id], tasks.distinct.pluck(:owner_id)
    LightekSales::Tasks.new(actor: @owner, site: @site).create!(kind: 'prospect', id: other.id,
      values: {title: 'Older due task', owner_id: @member.id, due_at: 2.days.ago})

    @prospecting.record_outreach!(prospect, outcome: 'Reply received', notes: 'Asked for a quote')
    get today_path, headers: headers
    assert_includes response.body, 'Reply received'
    assert_operator response.body.index('Review reply'), :<, response.body.index('Older due task')
    @prospecting.record_outreach!(prospect, outcome: 'No response', notes: '')
    get today_path, headers: headers
    assert_operator response.body.index('Older due task'), :<, response.body.index('Review reply')

    post block_contact_dashboard_sales_prospect_path(prospect, site_id: @site.id),
      params: {authenticity_token: token}, headers: headers
    assert_equal ['canceled', 'canceled'], tasks.pluck(:status)
    foreign = LightekSales::ProspectingCadences.new(actor: @other, site: @foreign_site)
    assert_raises(ActiveRecord::RecordNotFound) { foreign.apply!(**options, prospect_id: prospect.id) }
  end

  def test_prospecting_saves_google_maps_business_and_a_website_finding
    save_path = save_web_dashboard_sales_prospecting_path(site_id: @site.id)
    details = {provider: 'google_maps', display_name: 'Peachtree Accounting',
      listing_url: 'https://maps.app.goo.gl/examplePlace?g_st=ic', website_url: 'https://accounting.example.test/contact#about',
      website_finding: 'The mobile contact form does not submit.'}
    Net::HTTP.stub(:start, ->(*) { flunk 'Saving a Maps link must not contact any external site' }) do
      2.times do
        post save_path, params: details.merge(authenticity_token: token), headers: headers
        assert_response :see_other
      end
      prospect = LightekSales::SocialProspect.where(site: @site, provider: 'google_maps').sole
      assert_equal 'Peachtree Accounting', prospect.name
      assert_equal 'https://maps.app.goo.gl/examplePlace', prospect.source_url
      assert_equal 'https://accounting.example.test/contact', prospect.business_website_url

      get dashboard_sales_prospecting_path(site_id: @site.id, prospect_id: prospect.id), headers: headers
      assert_response :success
      page = Nokogiri::HTML(response.body)
      search = page.at_css('form[action="https://www.google.com/maps/search/"]')
      assert_equal '1', search.at_css('input[name="api"]')['value']
      assert search.at_css('input[name="query"]')
      assert_includes response.body, details.fetch(:website_finding)
      assert_equal prospect.business_website_url, page.at_css('[data-prospect-draft] a')['href']
      assert_includes response.body, 'Schedule follow-up'
      assert_nil @prospecting.account
    end

    web = LightekSales::WebProspecting.new(actor: @owner, site: @site)
    assert_raises(ArgumentError) do
      web.save_maps_business!(listing_url: 'https://maps.app.goo.gl.example.test/fake',
        name: 'Wrong domain', website_url: nil, finding: nil)
    end
    assert_raises(ArgumentError) do
      web.save_maps_business!(listing_url: details[:listing_url], name: details[:display_name],
        website_url: 'javascript:alert(1)', finding: nil)
    end
    prospect = web.save_maps_business!(listing_url: 'https://maps.google.com/?cid=12345', name: 'A second business',
      website_url: nil, finding: 'No website listed.')
    assert_equal 'https://www.google.com/maps?cid=12345', prospect.profile_url
    assert_nil prospect.business_website_url
  end

  def test_prospecting_follow_up_uses_the_sales_queue_and_honors_do_not_contact
    prospect = @prospecting.save_web_post!('https://x.com/TaylorWorks/status/123')
    focused_path = dashboard_sales_prospecting_path(site_id: @site.id, prospect_id: prospect.id)
    scheduled = {record_kind: 'prospect', record_id: prospect.id, request_key: 'x-follow-up-1',
      task: {title: 'Review the X reply', due_at: 1.minute.ago.iso8601, owner_id: @member.id}}

    get focused_path, headers: headers
    assert_response :success
    assert_includes response.body, 'Schedule follow-up'
    2.times do
      post dashboard_sales_tasks_path(site_id: @site.id), params: scheduled.merge(authenticity_token: token), headers: headers
      assert_redirected_to focused_path
    end
    task = LightekSales::Task.where(record: prospect).sole
    assert_equal @member, task.owner

    get dashboard_sales_path(site_id: @site.id, owner_id: @member.id), headers: headers
    assert_response :success
    assert_includes response.body, task.title
    assert_equal focused_path, Nokogiri::HTML(response.body).css('a').find { |link| link.text == prospect.name }['href']

    patch dashboard_sales_task_path(site_id: @site.id, id: task.id),
      params: {authenticity_token: token, task: {action: 'complete', lock_version: task.lock_version}}, headers: headers
    assert_equal 'completed', task.reload.status
    assert_equal @owner, task.completed_by
    assert_equal %w[task_created task_completed], LightekSales::Activity.where(record: prospect).order(:id).pluck(:kind)

    pending_task = LightekSales::Tasks.new(actor: @owner, site: @site).create!(
      kind: 'prospect', id: prospect.id, values: {title: 'Check back', owner_id: @owner.id, due_at: 1.day.from_now})
    post block_contact_dashboard_sales_prospect_path(prospect, site_id: @site.id),
      params: {authenticity_token: token}, headers: headers
    assert_response :see_other
    assert_equal 'canceled', pending_task.reload.status
    assert_equal 'completed', task.reload.status
    Net::HTTP.stub(:start, ->(*) { flunk 'Recording outreach must not send a message' }) do
      post outreach_dashboard_sales_prospect_path(prospect, site_id: @site.id),
        params: {authenticity_token: token, outreach: {outcome: 'Reply received', notes: 'Asked for a portfolio'}}, headers: headers
      assert_redirected_to focused_path
    end
    get focused_path, headers: headers
    assert_includes response.body, 'Asked for a portfolio'
    assert_includes response.body, 'Task canceled'
    assert_not_includes response.body, 'Schedule follow-up'
    assert_equal @owner, LightekSales::Activity.where(record: prospect, kind: 'outreach').sole.actor
    assert_raises(ArgumentError) do
      LightekSales::Tasks.new(actor: @owner, site: @site).create!(kind: 'prospect', id: prospect.id, values: scheduled[:task])
    end
    assert_raises(ActiveRecord::RecordNotFound) do
      LightekSales::Tasks.new(actor: @other, site: @foreign_site).create!(kind: 'prospect', id: prospect.id, values: scheduled[:task])
    end
  end

  def test_prospecting_search_save_send_and_link_lead
    with_provider do
      prospect = capture_http
      message_http(prospect, confirmed: '0')
      assert_equal 'ready', prospect.reload.outreach_status
      message_http(prospect)
      assert_equal 'sent', prospect.reload.outreach_status
      assert_equal '300', prospect.provider_message_id
      assert_equal @owner, prospect.contacted_by
      message_http(prospect)
      assert_equal 1, @calls.count { |request| request.method == 'POST' }

      post lead_dashboard_sales_prospect_path(prospect, site_id: @site.id),
        params: {authenticity_token: token, confirmed: '1', lead: {name: 'Taylor Buyer', email: 'taylor@example.test'}}, headers: headers
      lead = prospect.reload.lead
      assert_redirected_to dashboard_sales_record_path(kind: 'lead', id: lead.id, site_id: @site.id)
      assert_equal 'x', lead.source
      assert_equal 0, LightekMarketing::Contact.count
      assert LightekVault::AuditEvent.where(action: 'checkout', purpose: 'social_prospecting', allowed: true).exists?
    end
  end

  def test_prospecting_timeout_and_opt_out_prevent_replay
    with_provider(status: :timeout) do
      prospect = capture_http
      message_http(prospect)
      assert_response :see_other
      assert_equal 'uncertain', prospect.reload.outreach_status
      assert_nil prospect.provider_message_id
      message_http(prospect)
      assert_equal 1, @calls.count { |request| request.method == 'POST' }
      post block_contact_dashboard_sales_prospect_path(prospect, site_id: @site.id), params: {authenticity_token: token}, headers: headers
      assert prospect.reload.contact_blocked_at?
    end
  end

  def test_prospecting_isolates_credentials_results_and_saved_records
    with_provider do
      @prospecting.connect!(TOKEN)
      selection = @prospecting.search('"need a web designer"').first.fetch(:selection)
      foreign = LightekSales::XProspecting.new(site: @foreign_site, actor: @other)
      member = LightekSales::XProspecting.new(site: @site, actor: @member)
      assert_raises(ActiveRecord::RecordNotFound) { member.connect!(TOKEN) }
      assert_raises(ActiveRecord::RecordNotFound) { member.save!(selection) }
      assert_raises(ActiveRecord::RecordNotFound) { foreign.save!(selection) }
      assert_raises(LightekSales::XProspecting::Error) { @prospecting.save!('forged') }
      assert_raises(ActionController::InvalidAuthenticityToken) do
        post save_dashboard_sales_prospecting_path(site_id: @site.id), params: {selection: selection}, headers: headers
      end
      assert_empty LightekSales::SocialProspect.all
      @prospecting.disconnect!
      assert_nil @prospecting.account
      assert_raises(LightekSales::XProspecting::Error) { @prospecting.search('"need a web designer"') }
    end
  end

  def test_prospecting_explicit_rejection_preserves_ability_to_correct_and_send
    with_provider(status: 403) do
      prospect = capture_http
      message_http(prospect)
      assert_response :see_other
      assert_equal 'ready', prospect.reload.outreach_status
      assert_nil prospect.provider_message_id
    end
  end
end
