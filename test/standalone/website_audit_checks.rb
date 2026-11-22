# Native CMS render, real metadata partial, source analysis and guarded writes.
# The existing host substitutes private engine record/registry/auth interfaces.
# No outbound HTTP or browser JavaScript is used to produce audit evidence.
gem 'minitest', '~>5.0'
require 'minitest/mock'
require_relative 'site_content_checks'
ActiveRecord::Schema.define do
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
