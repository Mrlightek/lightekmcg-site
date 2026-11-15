class Dashboard::WebsiteAuditsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :set_audit_site
  rescue_from LightekGrowth::Audits::Source::Limit, ActiveRecord::RecordInvalid, ArgumentError, ActiveRecord::StaleObjectError do |error|
    redirect_to dashboard_website_audits_path(site_id: @site.id), alert: error.is_a?(ActiveRecord::StaleObjectError) ? 'This review changed. Reopen the latest state.' : error.message, status: :see_other
  end
  def index
    @runs = LightekGrowth::WebsiteAudit.where(site: @site).order(id: :desc).limit(10)
    @audit = params[:audit_id].present? ? LightekGrowth::WebsiteAudit.where(site: @site).find(params[:audit_id]) : @runs.first
    @findings = @audit ? @audit.findings.order(Arel.sql("CASE severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END"), :page_id, :id) : []
    @fixes = LightekGrowth::AuditFix.where(site: @site).includes(:finding, :created_by, :applied_by, :rolled_back_by).order(id: :desc).limit(20)
    @can_write = LightekSettings::WebsiteIdentity.sites_for(current_user).exists?(id: @site.id)
  end
  def create
    audit = LightekGrowth::Audits::Runner.new(actor: current_user, site: @site).run!(request_key: params[:request_key])
    redirect_to dashboard_website_audits_path(site_id: @site.id, audit_id: audit.id), notice: 'Native website audit recorded. Review coverage and evidence before making changes.', status: :see_other
  end
  def prepare_fix
    fixes.prepare!(finding_id: params[:finding_id], value: params[:value])
    redirect_to dashboard_website_audits_path(site_id: @site.id, anchor: 'review-changes'), notice: 'Change preview prepared. Review the saved before/after values, then explicitly apply.', status: :see_other
  end
  def apply_fix
    raise ArgumentError, 'Confirm the saved change preview.' unless params[:confirmed] == '1'
    fixes.apply!(id: params[:id], version: params[:lock_version])
    redirect_to dashboard_website_audits_path(site_id: @site.id, anchor: 'review-changes'), notice: 'Saved change applied and recheck attempted. Inspect its verification result.', status: :see_other
  end
  def rollback_fix
    raise ArgumentError, 'Confirm the rollback.' unless params[:confirmed] == '1'
    fixes.rollback!(id: params[:id], version: params[:lock_version])
    redirect_to dashboard_website_audits_path(site_id: @site.id, anchor: 'review-changes'), notice: 'Prior source restored and recheck attempted.', status: :see_other
  end
  def recheck_fix
    fix = LightekGrowth::AuditFix.where(site: @site).find(params[:id])
    raise ArgumentError, 'Apply a change before checking its result.' if fix.status == 'prepared'
    fixes.verify!(fix)
    redirect_to dashboard_website_audits_path(site_id: @site.id, anchor: 'review-changes'), notice: 'Verification attempted against a new page audit.', status: :see_other
  end
  def dismiss
    finding = LightekGrowth::AuditFinding.where(site: @site).find(params[:id])
    note = params[:note].to_s.strip
    raise ArgumentError, 'Explain the review decision (1–1000 characters).' unless note.length.in?(1..1000)
    finding.with_lock do
      @access.read!
      raise ActiveRecord::StaleObjectError.new(finding, 'update') unless params[:lock_version].to_s == finding.lock_version.to_s
      raise ArgumentError, 'This finding has already been resolved or dismissed.' unless finding.status == 'open'
      finding.update!(status: 'dismissed', resolved_by: current_user, resolved_at: Time.current, resolution_note: note)
    end
    redirect_to dashboard_website_audits_path(site_id: @site.id, audit_id: finding.website_audit_id), notice: 'Review decision recorded. A later audit will assess the actual source again.', status: :see_other
  end
  private
  def fixes = LightekGrowth::Audits::Fixes.new(actor: current_user, site: @site)
  def set_audit_site
    @sites = LightekSales::Access.sites_for(current_user).order(:name)
    @site = @sites.find(params.require(:site_id))
    @access = LightekGrowth::Audits::Access.new(actor: current_user, site: @site)
  end
end
