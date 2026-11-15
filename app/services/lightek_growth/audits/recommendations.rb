module LightekGrowth
  module Audits
    module Recommendations
      def self.call(site)
        audit = WebsiteAudit.where(site: site, scope_page_id: nil).order(id: :desc).first
        open = audit ? audit.findings.where(status: 'open') : AuditFinding.none
        {'website_audit_id' => audit&.id, 'website_audit_stale' => audit.nil? || audit.created_at < 7.days.ago,
         'website_audit_incomplete' => audit && (audit.status == 'partial' || audit.summary['published_pages'].to_i == 0), 'website_audit_open' => open.count, 'website_audit_high' => open.where(severity: 'high').count,
         'website_audit_unassessed' => audit ? audit.page_results.count { |row| row['status'] != 'assessed' } + [audit.summary['published_pages'].to_i - audit.page_results.size, 0].max : 0}
      end
    end
  end
end
