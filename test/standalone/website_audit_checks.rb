# Native CMS render, real metadata partial, source analysis and guarded writes.
# The existing host substitutes private engine record/registry/auth interfaces.
# No outbound HTTP or browser JavaScript is used to produce audit evidence.
gem 'minitest', '~>5.0'
require 'minitest/mock'
require_relative 'site_content_checks'
ActiveRecord::Schema.define do
  create_table(:nevaeh_goals) { |t| t.references :user; t.string :title; t.string :request_key; t.string :status, default: 'draft'; t.string :error; t.timestamps }
  create_table(:lightek_marketing_deliveries) { |t| t.references :campaign }
  create_table(:lightek_agency_site_memberships) { |t| t.references :site; t.references :user; t.references :granted_by; t.string :role }
end
require Rails.root.join('app/models/lightek_agency/site_membership')
require Rails.root.join('app/services/lightek_agency/access')
require Rails.root.join('app/services/lightek_sales/access')
module LightekAgency
  class PackagePolicy
    class Denied < StandardError; end
    class << self
      attr_accessor :disabled
      def authorize!(_user, feature)
        raise Denied, "#{feature} disabled" if Array(disabled).include?(feature)
        true
      end
    end
  end
end
require Rails.root.join('db/migrate/20261115190000_add_website_growth_audits')
AddWebsiteGrowthAudits.new.migrate(:up)
%w[page_metadata website_audit audit_finding audit_fix].each { |file| require Rails.root.join("app/models/lightek_growth/#{file}") }
%w[access source renderer analyzer runner fixes recommendations].each { |file| require Rails.root.join("app/services/lightek_growth/audits/#{file}") }
require Rails.root.join('app/services/lightek_growth/playbook')
require Rails.root.join('app/controllers/lightek_growth/audit_pages_controller')
require Rails.root.join('db/migrate/20261122090000_add_growth_search_evidence')
AddGrowthSearchEvidence.new.migrate(:up)
ActiveRecord::Schema.define do
  create_table(:lightek_growth_briefs) { |t| t.bigint :site_id; t.text :offering }
end
require Rails.root.join('app/models/lightek_growth/brief')
%w[backlink search_snapshot].each { |file| require Rails.root.join("app/models/lightek_growth/#{file}") }
%w[workspace backlink_work search_console].each { |file| require Rails.root.join("app/services/lightek_growth/#{file}") }
require Rails.root.join('app/controllers/dashboard/search_growth_controller')
Dashboard::SearchGrowthController.layout false
Rails.application.routes.append do
  eval(File.readlines(Rails.root.join('config/routes/growth.rb')).grep(/dashboard\/growth\/search/).join, binding)
end
Rails.application.reload_routes!
require Rails.root.join('db/migrate/20261122090100_record_nevaeh_website_changes')
RecordNevaehWebsiteChanges.new.migrate(:up)
require Rails.root.join('app/models/lightek_growth/website_change')
require Rails.root.join('app/services/nevaeh_os/website_marketing')
require Rails.root.join('app/services/nevaeh_os/website_journal')
require Rails.root.join('app/services/nevaeh_os/goals')
require Rails.root.join('app/services/nevaeh_os/journal_editorial')
require Rails.root.join('app/services/nevaeh_os/web_document')
require Rails.root.join('app/models/nevaeh_goal')
require Rails.root.join('db/migrate/20261028173000_create_lightek_marketing_campaigns')
CreateLightekMarketingCampaigns.new.migrate(:up)
ActiveRecord::Schema.define { add_column :lightek_marketing_campaigns, :media_url, :string }
require Rails.root.join('db/migrate/20261115160000_add_campaign_content_review')
AddCampaignContentReview.new.migrate(:up)
require Rails.root.join('app/models/lightek_marketing/campaign')
require Rails.root.join('app/models/lightek_marketing/content_variant')
require Rails.root.join('app/services/lightek_marketing/content_workbench')
require Rails.root.join('app/services/nevaeh_intelligences/writing_engine')
require Rails.root.join('app/services/nevaeh_intelligences/editorial_direction')
require Rails.root.join('app/controllers/dashboard/website_audits_controller')
Dashboard::WebsiteAuditsController.layout false
DymondSite::Page.has_one :growth_page_metadata, class_name: 'LightekGrowth::PageMetadata', foreign_key: :page_id, dependent: :destroy
class WebsiteAuditChecks < SiteContentChecks
  def self.runnable_methods = instance_methods.grep(/^test_audit_/).map(&:to_s)
  def setup
    super
    LightekAgency::PackagePolicy.disabled = []
    @marketer = User.create!(role: 'employee', email_address: "marketer-#{SecureRandom.hex(4)}@example.test")
    LightekAgency::SiteMembership.create!(site: @site, user: @marketer, granted_by: @user, role: 'marketer')
    workspace = LightekDesign::StudioDocument.create!(user: @user, name: 'Audit test website')
    document = LightekDesign::StudioDocument.draft(workspace)
    hero = LightekDesign::StudioDocument.new_block('hero')
    hero['data'].merge!('heading' => 'Run your business from one place', 'cta_label' => 'Learn more', 'cta_url' => '/site/missing', 'image_url' => 'https://images.example.test/offer.png', 'image_alt' => '')
    document['sections'] = [hero]
    release = LightekDesign::StudioDocument.publish!(record: workspace, document: document, expected_revision: LightekDesign::StudioDocument.revision(workspace))
    LightekDesign::WebsiteDesigns.apply!(site: @site, design: release.key)
    @page = LightekDesign::WebsiteDesigns.import!(site: @site, design: release.key)
    @page.update!(published: true, slug: 'home', title: 'A long business page title ' * 4)
    @section = @page.sections.first
  end
  def runner(actor = @user, site = @site) = LightekGrowth::Audits::Runner.new(actor: actor, site: site)
  def fixer(actor = @user, site = @site) = LightekGrowth::Audits::Fixes.new(actor: actor, site: site)
  def audit = runner.run!(request_key: SecureRandom.uuid)
  def finding(rule) = audit.findings.find_by!(rule: rule, page_id: @page.id)
  def preview(rule: 'description_missing', value: 'Business tools, creative production and managed services from Lightek.')
    fixer.prepare!(finding_id: finding(rule).id, value: value)
  end
  def html = LightekGrowth::Audits::Renderer.call(@page.reload)
  def test_audit_editorial_schedule_selects_new_approved_material_and_prepares_public_sharing
    marketing = NevaehOs::WebsiteMarketing
    editorial = NevaehOs::JournalEditorial
    @site.update!(manifest: @site.manifest.merge(marketing::KEY => { 'actor_id' => @user.id, 'key' => 'editorial-grant' }))
    source = 'https://journal-source.test/updates'
    config = { topics: "Studio
Payroll", sources: source, cadence: 'weekly', article_status: 'published', social_draft: '1' }
    patch '/dashboard/blog/configure_editorial', params: { site_id: @site.id, editorial: config }, headers: headers
    assert_response :see_other
    schedule = LightekBlog::EditorialSchedule.find_by!(site: @site)
    assert schedule.enabled?
    assert schedule.social_draft?
    assert_operator schedule.next_run_at, :<=, Time.current

    now = Time.current
    plan = NevaehGoal.create!(user: @user, title: 'Editorial cycle', request_key: 'editorial-fixture')
    captures = []
    create = ->(actor:, values:, request_key:) { captures << [actor, values, request_key]; plan }
    start = ->(goal:, actor:, operation:) { assert_equal [plan, @user, 'start'], [goal, actor, operation]; goal.update!(status: 'running') }
    NevaehOs::Goals.stub(:create!, create) do
      NevaehOs::Goals.stub(:control!, start) do
        editorial.dispatch!(schedule, now: now)
        editorial.dispatch!(schedule, now: now)
      end
    end
    assert_equal 1, captures.length
    assert_in_delta (now + 1.week).to_f, schedule.reload.next_run_at.to_f, 0.001
    steps = captures.first[1].fetch('steps')
    assert_equal %w[research article promote], steps.pluck('key')
    assert_equal({ '$step' => 'research', 'path' => 'result.story' }, steps[1].dig('command', 'values', 'story'))

    read = ->(url, follow_redirects:) do
      assert_equal source, url
      refute follow_redirects
      { url: source, title: 'Creator tools update', sha256: 'source-digest', body: "Unrelated
Lightek Studio now helps creators record and edit interviews together from their own computers." }
    end
    research = marketing.bind(@user, steps[0].fetch('command'))
    NevaehOs::WebDocument.stub(:fetch, read) do
      story = marketing.perform!(actor: @user, command: research, action_id: 201).fetch('story')
      assert_equal 'Studio', story.fetch('topic')
      write = marketing.bind(@user, steps[1].fetch('command'))
      write['values']['story'] = story
      saved = marketing.perform!(actor: @user, command: write, action_id: 202)
      assert saved.fetch('published')
      assert_equal source, saved.fetch('source_url')
      get saved.fetch('path')
      assert_response :success
      assert_includes response.body, 'href="https://journal-source.test/updates"'
      assert_includes response.body, 'Share to'
      assert_includes response.body, 'linkedin.com/sharing/share-offsite'
      assert_raises(ArgumentError) { marketing.perform!(actor: @user, command: research, action_id: 203) }

      promote = marketing.bind(@user, steps[2].fetch('command'))
      promote['values']['entry_id'] = saved.fetch('entry_id')
      promotion = marketing.perform!(actor: @user, command: promote, action_id: 204)
      assert_equal 'draft', promotion.fetch('campaign_status')
      assert_equal promotion, marketing.perform!(actor: @user, command: promote, action_id: 204)
      draft = LightekMarketing::ContentVariant.find(promotion.fetch('variant_id'))
      assert_equal "https://#{@site.host}#{saved.fetch('path')}", draft.cta_url
      assert_equal saved.fetch('entry_id'), draft.source_snapshot.fetch('journal_entry_id')
      workbench = LightekMarketing::ContentWorkbench.new(actor: @user, site: @site)
      workbench.send(:validate_source!, draft)
      draft.cta_url = 'https://different.test/article'
      assert_raises(ArgumentError) { workbench.send(:validate_source!, draft) }
      editorial.pause!(site: @site, actor: @user)
      assert_raises(ArgumentError) { marketing.perform!(actor: @user, command: write, action_id: 205) }
    end
  end

  def test_audit_delegated_marketing_writes_and_publishes_native_journal_articles
    operator = NevaehOs::WebsiteMarketing
    grant = { 'actor_id' => @user.id, 'key' => 'fixture-grant' }
    @site.update!(manifest: @site.manifest.merge(operator::KEY => grant))
    get '/dashboard/blog', params: { site_id: @site.id }, headers: headers
    assert_response :success
    assert_includes response.body, 'Assign an article to Nevaeh'
    assert_includes response.body, '/dashboard/blog/assign_nevaeh'

    create_goal = lambda do |actor:, request_key:, values:|
      assert_equal @user, actor
      assert_match(/\Ajournal-#{@site.id}-/, request_key)
      step = values.fetch('steps').sole
      assert_equal 'marketing_strategy', step.fetch('agent')
      assert_equal 'journal_write', step.dig('command', 'operation')
      assert_equal 'draft', step.dig('command', 'values', 'status')
      Struct.new(:id, :status).new(123, 'draft')
    end
    start_goal = ->(goal:, actor:, operation:) { assert_equal [123, @user, 'start'], [goal.id, actor, operation] }
    NevaehOs::Goals.stub(:create!, create_goal) do
      NevaehOs::Goals.stub(:control!, start_goal) do
        post '/dashboard/blog/assign_nevaeh', params: { site_id: @site.id, request_key: SecureRandom.uuid,
          assignment: { title: 'Inside Lightek Studio', facts: 'Creators can edit a show in Lightek Studio.' } }, headers: headers
        assert_response :see_other
      end
    end

    draft = operator.bind(@user, { 'site_id' => @site.id, 'operation' => 'journal_write', 'values' => {
      'title' => 'Inside Lightek Studio', 'category' => 'News',
      'brief' => { 'facts' => 'Creators can record and edit a show in Lightek Studio.' }
    } })
    receipt = operator.perform!(actor: @user, command: draft, action_id: 11)
    assert_equal 'draft', receipt.fetch('article_status')
    assert_equal receipt, operator.perform!(actor: @user, command: draft, action_id: 11)
    path = receipt.fetch('path')
    get path
    assert_response :not_found

    entry = LightekBlog::Entry.find(receipt.fetch('entry_id'))
    inspect_command = draft.merge('operation' => 'journal_inspect', 'values' => { 'entry_id' => entry.id })
    article = operator.perform!(actor: @user, command: inspect_command, action_id: 12)
    assert_includes article.fetch('content'), 'Creators can record and edit a show in Lightek Studio.'
    revised = LightekBlog::Editor.save!(site: @site, user: @user, entry: entry,
      attributes: { title: entry.post.title, content: article.fetch('content') + "\n\nA note from the editor.", slug: entry.slug,
        category: entry.category, status: entry.status, lock_version: entry.lock_version })
    publish = draft.merge('values' => { 'entry_id' => entry.id, 'revision' => article.fetch('revision'), 'status' => 'published' })
    assert_raises(ArgumentError) { operator.perform!(actor: @user, command: publish, action_id: 13) }
    publish['values']['revision'] = revised.lock_version
    live = operator.perform!(actor: @user, command: publish, action_id: 13)
    assert live.fetch('published')
    get path
    assert_response :success
    assert_includes response.body, 'A note from the editor.'
    get '/journal.xml'
    assert_response :success
    assert_includes response.body, 'Inside Lightek Studio'

    foreign_entry = LightekBlog::Editor.save!(site: @foreign, user: @other,
      attributes: { title: 'Other news', content: 'Private facts', slug: 'other-news' })
    assert_raises(ActiveRecord::RecordNotFound) do
      operator.perform!(actor: @user, command: inspect_command.merge('values' => { 'entry_id' => foreign_entry.id }), action_id: 14)
    end
    @site.update!(manifest: @site.reload.manifest.except(operator::KEY))
    assert_raises(ArgumentError) { operator.perform!(actor: @user, command: publish, action_id: 15) }
  end

  def test_audit_delegated_marketing_renders_public_copy_and_rejects_stale_or_revoked_work
    operator = NevaehOs::WebsiteMarketing
    @site.update!(manifest: @site.manifest.merge(operator::KEY => { 'actor_id' => @user.id, 'key' => 'fixture-grant' }))
    values = { 'title' => 'Book Studio', 'slug' => 'book-studio', 'published' => true, 'description' => 'Book a production session.',
      'sections' => [{ 'block' => 'hero', 'data' => { 'heading' => 'Make your next show', 'body' => 'Record, edit and publish.' } }] }
    command = operator.bind(@user, { 'site_id' => @site.id, 'operation' => 'compose', 'values' => values })
    receipt = operator.perform!(actor: @user, command: command, action_id: 1)
    assert receipt.fetch('published')
    assert_equal receipt, operator.perform!(actor: @user, command: command, action_id: 1)

    @site.update!(manifest: @site.reload.manifest.merge('hosted_application_key' => 'test'))
    get '/site/book-studio'
    assert_response :success
    assert_includes response.body, 'Make your next show'
    assert_includes response.body, 'Book a production session.'

    page = @site.pages.find(receipt.fetch('page_id'))
    updated = command.merge('values' => values.merge('page_id' => page.id, 'revision' => receipt.fetch('revision'), 'title' => 'Updated page'))
    update_receipt = operator.perform!(actor: @user, command: updated, action_id: 2)
    restore = command.merge('operation' => 'restore', 'values' => {
      'page_id' => page.id, 'revision' => update_receipt.fetch('revision'), 'change_id' => update_receipt.fetch('change_id')
    })
    restored = operator.perform!(actor: @user, command: restore, action_id: 3)
    assert_equal 'Book Studio', page.reload.title
    assert restored.fetch('published')

    inspected = operator.perform!(actor: @user, command: command.merge('operation' => 'inspect', 'values' => {}), action_id: 4)
    appearance = command.merge('operation' => 'appearance', 'values' => {
      'revision' => inspected.fetch('appearance_revision'), 'design' => 'vinylctrl', 'colors' => { 'color_primary' => '#112233' }
    })
    result = operator.perform!(actor: @user, command: appearance, action_id: 5)
    assert_equal '#112233', @site.reload.active_template.settings.dig('tokens', 'color_primary')
    refute_equal inspected.fetch('appearance_revision'), result.fetch('appearance_revision')

    page.update!(title: 'A newer edit')
    publish = command.merge('operation' => 'publication', 'values' => {
      'page_id' => page.id, 'revision' => receipt.fetch('revision'), 'published' => false
    })
    assert_raises(ArgumentError) { operator.perform!(actor: @user, command: publish, action_id: 6) }
    assert page.reload.published?
    assert_raises(ActiveRecord::RecordNotFound) do
      operator.perform!(actor: @user, command: command.merge('site_id' => @foreign.id), action_id: 7)
    end

    operator.configure!(actor: @user, site_id: @site.id, enabled: false)
    assert_raises(ArgumentError) { operator.perform!(actor: @user, command: command, action_id: 8) }
    assert_equal 4, LightekGrowth::WebsiteChange.where(site_id: @site.id).count
  end

  def test_audit_search_growth_import_and_draft_permissions
    work = LightekGrowth::BacklinkWork.new(actor: @user, site: @site)
    target = "https://#{@site.host}/site/home"
    source = 'https://publication.test/article'
    prospect = work.record!(source: source, target: target, status: 'prospect')
    assert_raises(ArgumentError) { work.authorize_draft!(id: prospect.id, version: 'outdated') }
    assert_raises(ActiveRecord::RecordNotFound) do
      LightekGrowth::BacklinkWork.new(actor: @other, site: @foreign).authorize_draft!(id: prospect.id, version: prospect.updated_at.iso8601(6))
    end
    draft = work.authorize_draft!(id: prospect.id, version: prospect.updated_at.iso8601(6))
    assert_equal @user.id, draft.approved_by_id
    assert_includes draft.outreach_draft, target

    work.record!(source: source, target: target, status: 'lost')
    csv = "Source URL,Target URL\n#{source},#{target}\n"
    assert_equal 1, work.import!(StringIO.new(csv))
    assert_equal 'lost', prospect.reload.status
    assert_nil prospect.approved_at
    assert_equal 1, LightekGrowth::Backlink.where(site: @site).count

    get dashboard_search_growth_path(site_id: @site.id), headers: headers
    assert_response :success
    assert_includes response.body, 'Search &amp; backlinks'
    assert_includes response.body, source
  end

  def test_audit_search_console_scopes_results_and_records_observed_metrics
    sync = LightekGrowth::SearchConsole.new(actor: @user, site: @site)
    requests = []
    page = "https://#{@site.host}/site/home"
    sync.define_singleton_method(:post) do |uri, data, token: nil|
      requests << [uri, data, token]
      case uri.host
      when 'oauth2.googleapis.com' then { 'access_token' => 'fixture' }
      when 'www.googleapis.com'
        row = { 'keys' => [page, 'business software'], 'clicks' => 2, 'impressions' => 200, 'ctr' => 0.01, 'position' => 5 }
        { 'rows' => [row, row.merge('keys' => ['https://other.test/', 'unrelated'])] }
      else
        { 'inspectionResult' => { 'indexStatusResult' => { 'verdict' => 'PASS' } } }
      end
    end
    credential = { 'client_id' => 'example', 'client_secret' => 'example', 'refresh_token' => 'example' }
    LightekVault::Service.stub(:checkout!, credential) do
      assert_raises(ArgumentError) { sync.sync!(inspection_url: 'https://other.test/') }
      snapshot = sync.sync!(inspection_url: page)
      assert_equal 3, requests.size
      assert_equal "https://#{@site.host}/", snapshot.property
      assert_equal 28, (snapshot.ends_on - snapshot.starts_on).to_i + 1
      assert_equal 1, snapshot.rows.size
      assert_equal page, snapshot.review_candidate.fetch('page')
      assert_equal 'PASS', snapshot.inspection.fetch('verdict')
    end
  end

  def test_audit_native_output_has_evidence_and_only_published_site_pages
    @site.pages.create!(title: 'Draft', slug: 'draft', published: false)
    @foreign.pages.create!(title: 'Foreign', slug: 'secret', published: true)
    report = audit
    assert_equal 'completed', report.status, report.page_results.inspect
    assert_equal 1, report.summary['assessed_pages']
    assert_equal [@page.id], report.page_results.map { |row| row['page_id'] }
    assert report.findings.exists?(rule: 'description_missing')
    assert report.findings.exists?(rule: 'internal_link_missing', severity: 'high')
    assert report.findings.exists?(rule: 'image_description_review', severity: 'low')
    assert report.findings.exists?(rule: 'cta_label_review')
    refute report.findings.exists?(rule: 'heading_missing')
    broken = report.findings.find_by!(rule: 'internal_link_missing')
    assert_equal '/site/missing', broken.evidence['href']
    assert_equal @section.id, broken.fix_target['section_id']
    assert_equal 'cta_url', broken.fix_target['field']
    assert_equal report.id, runner.run!(request_key: report.request_key).id
    assert_raises(ArgumentError) { runner.run!(request_key: report.request_key, page_id: @page.id) }
    assert_raises(ActiveRecord::RecordInvalid) { report.update!(summary: {}) }
    assert_raises(ActiveRecord::RecordInvalid) { broken.update!(evidence: {}) }
  end
  def test_audit_preview_apply_public_description_recheck_and_rollback
    fix = preview(value: 'Tools for creators <and> businesses.')
    refute LightekGrowth::PageMetadata.exists?(page: @page)
    refute_includes html, 'name="description"'
    assert_includes html, %(rel="canonical" href="https://#{@site.host}/site/home")
    assert_equal 'prepared', fix.status
    fixer.apply!(id: fix.id, version: fix.lock_version)
    assert_equal 'applied', fix.reload.status
    assert_equal 'verified_absent', fix.verification['status']
    assert_equal 'resolved', fix.finding.reload.status
    doc = Nokogiri::HTML5.parse(html)
    assert_equal 'Tools for creators <and> businesses.', doc.at_css('meta[name="description"]')['content']
    assert_includes html, '&lt;and&gt;'
    assert_equal @user, fix.applied_by
    assert_equal fix, fixer.apply!(id: fix.id, version: 0)
    fixer.rollback!(id: fix.id, version: fix.lock_version)
    assert_equal 'rolled_back', fix.reload.status
    refute LightekGrowth::PageMetadata.exists?(page: @page)
    assert_equal 'finding_present', fix.verification['status']
    assert_equal 'open', fix.finding.reload.status
    assert_equal @user, fix.rolled_back_by
    assert_equal fix, fixer.rollback!(id: fix.id, version: 0)
  end
  def test_audit_native_cta_change_preserves_other_fields_and_rechecks_actual_target
    @site.pages.create!(title: 'Services', slug: 'services', published: true)
    before = @section.data.deep_dup
    fix = preview(rule: 'internal_link_missing', value: '/site/services')
    assert_equal before, @section.reload.data
    fixer.apply!(id: fix.id, version: 0)
    assert_equal before.merge('cta_url' => '/site/services'), @section.reload.data
    assert_equal 'verified_absent', fix.reload.verification['status']
    assert_includes html, 'href="/site/services"'
    fixer.rollback!(id: fix.id, version: fix.lock_version)
    assert_equal before, @section.reload.data
  end
  def test_audit_alt_and_title_changes_render_and_preserve_source_fields
    before = @section.data.deep_dup
    fix = preview(rule: 'image_description_review', value: 'Lightek business workspace <overview>')
    fixer.apply!(id: fix.id, version: 0)
    assert_equal before.merge('image_alt' => 'Lightek business workspace <overview>'), @section.reload.data
    assert_equal 'verified_absent', fix.reload.verification['status']
    assert_equal 'Lightek business workspace <overview>', Nokogiri::HTML5.parse(html).at_css('img')['alt']
    fixer.rollback!(id: fix.id, version: fix.lock_version)
    assert_equal before, @section.reload.data
    title = preview(rule: 'title_length', value: 'Lightek <Business>')
    original_title = @page.title
    fixer.apply!(id: title.id, version: 0)
    assert_equal 'Lightek <Business>', Nokogiri::HTML5.parse(html).at_css('title').text
    assert_equal original_title, @page.reload.title
    assert_includes html, '&lt;Business&gt;'
    assert_equal 'verified_absent', title.reload.verification['status']
  end
  def test_audit_review_decision_records_actor_and_never_counts_as_verified_fix
    target = finding('image_description_review')
    path = dismiss_website_audit_finding_path(site_id: @site.id, id: target.id)
    patch path, params: {note: '', lock_version: 0}, headers: headers
    assert_equal 'open', target.reload.status
    patch path, params: {note: 'Decorative image in this design.', lock_version: 0}, headers: headers
    assert_response :see_other
    assert_equal 'dismissed', target.reload.status
    assert_equal @user, target.resolved_by
    assert_equal 'Decorative image in this design.', target.resolution_note
    assert_equal 0, LightekGrowth::AuditFix.count
    assert audit.findings.exists?(rule: 'image_description_review', status: 'open')
    patch path, params: {note: 'Overwritten decision', lock_version: 0}, headers: headers
    assert_equal 'Decorative image in this design.', target.reload.resolution_note
  end
  def test_audit_stale_previews_and_newer_manual_edits_are_not_overwritten
    fix = preview
    @page.update!(title: 'Changed in the CMS')
    assert_raises(ArgumentError) { fixer.apply!(id: fix.id, version: 0) }
    refute LightekGrowth::PageMetadata.exists?(page: @page)
    assert_raises(ArgumentError) { fixer.prepare!(finding_id: fix.finding_id, value: 'An old finding') }
    fresh = preview
    fixer.apply!(id: fresh.id, version: 0)
    row = LightekGrowth::PageMetadata.find_by!(page: @page)
    row.update!(description: 'Later editor change', updated_by: @user)
    assert_raises(ArgumentError) { fixer.rollback!(id: fresh.id, version: fresh.reload.lock_version) }
    assert_equal 'Later editor change', row.reload.description
  end
  def test_audit_marketer_can_read_but_cannot_gain_cms_write_permission
    report = runner(@marketer).run!(request_key: SecureRandom.uuid)
    target = report.findings.find_by!(rule: 'description_missing')
    assert_raises(ActiveRecord::RecordNotFound) { fixer(@marketer).prepare!(finding_id: target.id, value: 'No CMS rights') }
    assert_raises(ActiveRecord::RecordNotFound) { runner(@other) }
    cached = runner(@marketer)
    LightekAgency::SiteMembership.where(user: @marketer).delete_all
    assert_raises(ActiveRecord::RecordNotFound) { cached.run!(request_key: SecureRandom.uuid) }
    LightekAgency::PackagePolicy.disabled = ['design']
    assert_raises(LightekAgency::PackagePolicy::Denied) { fixer.prepare!(finding_id: target.id, value: 'Design disabled') }
    LightekAgency::PackagePolicy.disabled = ['marketing']
    assert_raises(LightekAgency::PackagePolicy::Denied) { runner }
  end
  def test_audit_unsupported_or_failed_pages_are_unassessed
    @site.update!(active_template: nil)
    report = audit
    assert_equal 'partial', report.status
    assert_equal 0, report.summary['assessed_pages']
    assert_equal 'unassessed', report.page_results.first['status']
    assert_equal 0, report.findings.count
    LightekGrowth::Audits::Renderer.stub(:call, ->(*) { raise 'simulated template failure' }) do
      second = audit
      assert_equal 'partial', second.status
      assert_equal 0, second.findings.count
      assert_includes second.page_results.first['reason'], 'RuntimeError'
    end
  end
  def test_audit_invalid_urls_scoped_findings_and_immutable_previews
    target = finding('internal_link_missing')
    assert_raises(ArgumentError) { fixer.prepare!(finding_id: target.id, value: 'javascript:alert(1)') }
    assert_raises(ArgumentError) { fixer.prepare!(finding_id: target.id, value: '//other.example.test/path') }
    assert_raises(ActiveRecord::RecordNotFound) { fixer(@other, @foreign).prepare!(finding_id: target.id, value: '/site/services') }
    fix = fixer.prepare!(finding_id: target.id, value: '/site/services')
    assert_raises(ActiveRecord::RecordInvalid) { fix.update!(after_values: {}) }
    assert_raises(ActiveRecord::StaleObjectError) { fixer.apply!(id: fix.id, version: 100) }
    assert_equal 'prepared', fix.reload.status
  end
  def test_audit_duplicate_title_recheck_does_not_claim_success_for_unchanged_title
    @page.update!(title: 'Same title')
    @site.pages.create!(title: 'Same title', slug: 'other', published: true)
    duplicate = finding('title_duplicate')
    fix = fixer.prepare!(finding_id: duplicate.id, value: 'Same title · Lightek business')
    fixer.apply!(id: fix.id, version: 0)
    assert_equal 'finding_present', fix.reload.verification['status']
    assert_equal 'open', duplicate.reload.status
    assert_equal 'Same title · Lightek business', Nokogiri::HTML5.parse(html).at_css('title').text
  end
  def test_audit_render_failure_after_apply_keeps_committed_change_and_can_recheck
    fix = preview
    LightekGrowth::Audits::Renderer.stub(:call, ->(*) { raise 'temporary render failure' }) do
      fixer.apply!(id: fix.id, version: 0)
    end
    assert_equal 'applied', fix.reload.status
    assert_equal 'unassessed', fix.verification['status']
    assert_equal fix.after_values['description'], LightekGrowth::PageMetadata.find_by!(page: @page).description
    fixer.verify!(fix)
    assert_equal 'verified_absent', fix.reload.verification['status']
  end
  def test_audit_full_site_evidence_drives_nevaeh_and_page_rechecks_do_not_replace_it
    report = audit
    facts = LightekGrowth::Audits::Recommendations.call(@site)
    assert_equal report.id, facts['website_audit_id']
    assert_operator facts['website_audit_high'], :>, 0
    runner.run!(request_key: SecureRandom.uuid, page_id: @page.id)
    assert_equal report.id, LightekGrowth::Audits::Recommendations.call(@site)['website_audit_id']
    base = {'review_inquiries' => 0, 'paid_undelivered' => 0, 'due_tasks' => 0, 'expiring_quotes' => 0, 'campaigns' => 1, 'enabled_links' => 1, 'tracked_visits' => 0}
    moves = LightekGrowth::Playbook.recommendations({'brief_complete' => true, 'brief' => {}, 'window_to' => Date.current.iso8601, 'facts' => base.merge(facts)})
    assert_equal 'website_audit', moves.first['key']
    assert_equal 'website_audit', moves.first['destination']
    assert_equal report.id, moves.first.dig('evidence', 'website_audit_id')
  end
  def test_audit_native_http_confirmations_history_and_rendered_dashboard
    post dashboard_website_audits_path(site_id: @site.id), params: {request_key: 'http-audit-1'}, headers: headers.except('X-CSRF-Token')
    assert_response :unprocessable_entity
    assert_equal 0, LightekGrowth::WebsiteAudit.count
    post dashboard_website_audits_path(site_id: @site.id), params: {request_key: 'http-audit-1'}, headers: headers
    assert_response :see_other
    report = LightekGrowth::WebsiteAudit.last
    target = report.findings.find_by!(rule: 'description_missing')
    post prepare_website_audit_fix_path(site_id: @site.id, finding_id: target.id), params: {value: 'Reviewed website description'}, headers: headers
    fix = LightekGrowth::AuditFix.last
    post apply_website_audit_fix_path(site_id: @site.id, id: fix.id), params: {lock_version: 0}, headers: headers
    assert_equal 'prepared', fix.reload.status
    post apply_website_audit_fix_path(site_id: @site.id, id: fix.id), params: {lock_version: 0, confirmed: '1', value: 'Unreviewed injected replacement'}, headers: headers
    assert_equal 'applied', fix.reload.status
    assert_equal 'Reviewed website description', LightekGrowth::PageMetadata.find_by!(page: @page).description
    get dashboard_website_audits_path(site_id: @site.id, audit_id: report.id), headers: headers
    assert_response :success
    assert_select 'h1', text: 'Website growth audit'
    assert_includes response.body, 'verified_absent'
    assert_includes response.body, 'Before'
    if ENV['SALES_PREVIEW_DIR']
      FileUtils.mkdir_p(ENV['SALES_PREVIEW_DIR'])
      File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'website-audit.html'), response.body)
    end
    get dashboard_website_audits_path(site_id: @foreign.id, audit_id: report.id), headers: headers(@other)
    assert_response :not_found
  end
  def test_audit_source_budgets_are_visible_and_page_metadata_cleans_up_with_page
    @section.update!(data: @section.data.merge('body' => 'x' * 270_000))
    report = audit
    assert_equal 'partial', report.status
    assert_equal 0, report.summary['assessed_pages']
    assert_includes report.page_results.first['reason'], '256 KB'
    @section.update!(data: @section.data.merge('body' => 'A concise offer'))
    fix = preview
    fixer.apply!(id: fix.id, version: 0)
    @page.destroy!
    refute LightekGrowth::PageMetadata.exists?(page_id: @page.id)
    assert LightekGrowth::AuditFix.exists?(fix.id)
  end
  def test_audit_imported_shadow_content_is_assessed_without_editing_raw_html
    theme = install(files: [file('index.html', '<main><h1>A real imported offer</h1><a href="/site/absent">Request a demo</a><img src="https://images.test/product.png"></main>')])
    LightekDesign::SiteTheme.activate!(site: @site, user: @user, template_id: theme.id)
    imported = @site.pages.find(theme.settings.dig('lightek_site_theme', 'pages').first['page_id'])
    imported.update!(published: true)
    report = runner.run!(request_key: SecureRandom.uuid, page_id: imported.id)
    assert_equal 'completed', report.status, report.page_results.inspect
    refute report.findings.exists?(rule: 'heading_missing')
    assert report.findings.exists?(rule: 'internal_link_missing')
    broken = report.findings.find_by!(rule: 'internal_link_missing')
    assert_equal({}, broken.fix_target)
    assert_raises(ArgumentError) { fixer.prepare!(finding_id: broken.id, value: '/site/home') }
  end
  def test_audit_per_page_fix_can_remain_present_and_network_is_not_contacted
    require 'net/http'
    report = nil
    Net::HTTP.stub(:start, ->(*) { raise 'Unexpected network request' }) { report = audit }
    assert_equal 'completed', report.status
    fix = fixer.prepare!(finding_id: report.findings.find_by!(rule: 'title_length').id, value: 'Still a long title ' * 5)
    fixer.apply!(id: fix.id, version: 0)
    assert_equal 'finding_present', fix.reload.verification['status']
    assert_equal 'open', fix.finding.reload.status
    assert_equal 'applied', fix.status
  end

end
