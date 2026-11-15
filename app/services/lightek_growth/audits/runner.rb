module LightekGrowth
  module Audits
    class Runner
      def initialize(actor:, site:)
        @actor, @site = actor, site
        @access = Access.new(actor: actor, site: site)
      end
      def run!(request_key:, page_id: nil)
        raise ArgumentError, 'Audit request key required.' unless request_key.to_s.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        @site.with_lock do
          @access.read!
          previous = WebsiteAudit.find_by(site: @site, request_key: request_key)
          if previous
            raise ArgumentError, 'Request key belongs to a different audit scope.' unless previous.summary['requested_page_id'].to_s == page_id.to_s
            return previous
          end
          scope = @site.pages.where(published: true).order(:id)
          scope = scope.where(id: page_id) if page_id
          pages = scope.limit(51).to_a
          raise ActiveRecord::RecordNotFound if page_id && pages.empty?
          partial = pages.size > 50
          results, findings, rendered = [], [], 0
          pages.first(50).each do |page|
            begin
              fingerprint = Source.fingerprint(page)
              html = Renderer.call(page)
              rendered += html.bytesize
              raise Source::Limit, 'Audit rendered-content budget exceeds 8 MB.' if rendered > 8_000_000
              raise ArgumentError, 'Page changed while rendering; rerun the audit.' unless Source.fingerprint(page.reload) == fingerprint
              rows = Analyzer.call(page: page, html: html)
              partial = true if rows.any? { |row| row[:rule] == 'scan_limit' }
              remaining = 200 - findings.size
              partial = true if rows.size > remaining
              findings.concat(rows.first([remaining, 0].max).map { |row| row.merge(page_id: page.id, evidence: row.fetch(:evidence).merge('page_path' => Source.path(page), 'fingerprint' => fingerprint)) })
              results << {'page_id' => page.id, 'path' => Source.path(page), 'status' => 'assessed', 'fingerprint' => fingerprint, 'findings' => rows.size}
            rescue StandardError => error
              partial = true
              results << {'page_id' => page.id, 'path' => Source.path(page), 'status' => 'unassessed', 'reason' => error.is_a?(Source::Limit) || error.is_a?(ArgumentError) ? error.message.first(200) : "Render failed: #{error.class.name}"}
              Rails.logger.warn({event: 'lightek.growth.audit_page_unassessed', site_id: @site.id, page_id: page.id, error_class: error.class.name}.to_json)
            end
          end
          audit = WebsiteAudit.create!(site: @site, created_by: @actor, request_key: request_key, scope_page_id: page_id, status: partial ? 'partial' : 'completed', rules_version: Analyzer::VERSION,
            page_results: results, summary: {'requested_page_id' => page_id, 'published_pages' => scope.count, 'assessed_pages' => results.count { |row| row['status'] == 'assessed' }, 'finding_count' => findings.size, 'limits' => '50 pages / 200 findings / native markup only'})
          findings.each { |row| audit.findings.create!(row.merge(site: @site)) }
          Rails.logger.info({event: 'lightek.growth.audit_completed', site_id: @site.id, actor_id: @actor.id, audit_id: audit.id, status: audit.status, findings: findings.size}.to_json)
          audit
        end
      end
    end
  end
end
