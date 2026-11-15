module LightekGrowth
  module Audits
    class Fixes
      def initialize(actor:, site:)
        @actor, @site = actor, site
        @access = Access.new(actor: actor, site: site)
      end
      def prepare!(finding_id:, value:)
        @access.write!
        finding = AuditFinding.where(site: @site).find(finding_id)
        page = @site.pages.where(published: true).find(finding.page_id)
        raise ArgumentError, 'This finding is no longer open.' unless finding.status == 'open'
        raise ArgumentError, 'Rerun the audit; this page changed.' unless Source.fingerprint(page) == finding.evidence['fingerprint']
        raise ArgumentError, 'Audit rules changed. Run a new audit.' unless finding.website_audit.rules_version == Analyzer::VERSION
        target = finding.fix_target
        validate_value!(target, value)
        with_target(page, target) do |record|
          @access.write!
          raise ArgumentError, 'Rerun the audit; source changed before preview.' unless Source.fingerprint(page.reload) == finding.evidence['fingerprint']
          before = values(record, target)
          after = before.merge(target.fetch('field') => value.to_s.strip)
          after['exists'] = true if target['kind'] == 'metadata'
          AuditFix.create!(site: @site, finding: finding, created_by: @actor, baseline: Source.fingerprint(page.reload), before_values: before, after_values: after).tap { |fix| log('audit_fix_prepared', fix) }
        end
      end
      def apply!(id:, version:)
        fix = AuditFix.where(site: @site).find(id)
        @access.write!
        fix.with_lock do
          return fix if fix.status == 'applied'
          raise ArgumentError, 'This preview has already been rolled back.' unless fix.status == 'prepared'
          version!(fix, version)
          raise ArgumentError, 'This finding is no longer open. Rerun the audit.' unless fix.finding.reload.status == 'open'
          raise ArgumentError, 'Audit rules changed. Run a new audit.' unless fix.finding.website_audit.rules_version == Analyzer::VERSION
          page = @site.pages.where(published: true).find(fix.finding.page_id)
          with_target(page, fix.finding.fix_target) do |record|
            @access.write!
            raise ArgumentError, 'Source changed. Prepare a fresh audit and preview.' unless Source.fingerprint(page.reload) == fix.baseline && values(record, fix.finding.fix_target) == fix.before_values
            write!(record, fix.finding.fix_target, fix.after_values)
            fix.update!(status: 'applied', applied_by: @actor, applied_at: Time.current, applied_fingerprint: Source.fingerprint(page.reload), verification: {'status' => 'pending'})
            log(fix.status == 'applied' ? 'audit_fix_applied' : 'audit_fix_rolled_back', fix)
          end
        end
        verify!(fix)
        fix
      end
      def rollback!(id:, version:)
        fix = AuditFix.where(site: @site).find(id)
        @access.write!
        fix.with_lock do
          return fix if fix.status == 'rolled_back'
          version!(fix, version)
          raise ArgumentError, 'Only an applied change can be rolled back.' unless fix.status == 'applied'
          page = @site.pages.where(published: true).find(fix.finding.page_id)
          with_target(page, fix.finding.fix_target) do |record|
            @access.write!
            raise ArgumentError, 'Source changed after application. Review it instead of overwriting newer edits.' unless Source.fingerprint(page.reload) == fix.applied_fingerprint && values(record, fix.finding.fix_target) == fix.after_values
            write!(record, fix.finding.fix_target, fix.before_values)
            fix.update!(status: 'rolled_back', rolled_back_by: @actor, rolled_back_at: Time.current, verification: {'status' => 'pending'})
            log(fix.status == 'applied' ? 'audit_fix_applied' : 'audit_fix_rolled_back', fix)
          end
        end
        verify!(fix)
        fix
      end
      def verify!(fix)
        @access.read!
        raise ActiveRecord::RecordNotFound unless fix.site_id == @site.id
        phase = fix.status
        audit = Runner.new(actor: @actor, site: @site).run!(request_key: "fix-#{fix.id}-#{SecureRandom.uuid}", page_id: fix.finding.page_id)
        assessed = audit.status == 'completed' && audit.page_results.any? { |row| row['page_id'] == fix.finding.page_id && row['status'] == 'assessed' }
        present = audit.findings.where(rule: fix.finding.rule, locator: fix.finding.locator).exists?
        fix.with_lock do
          return if fix.status != phase
          fix.update!(verification: {'status' => assessed ? (present ? 'finding_present' : 'verified_absent') : 'unassessed', 'audit_id' => audit.id})
          if assessed
            fix.finding.update!(status: present ? 'open' : 'resolved', resolved_by: @actor, resolved_at: Time.current, resolution_note: "Rechecked by audit ##{audit.id}; finding #{present ? 'present' : 'absent'}.")
          end
        end
        Rails.logger.info({event: 'lightek.growth.audit_fix_checked', site_id: @site.id, actor_id: @actor.id, fix_id: fix.id, status: fix.status, verification: fix.verification['status']}.to_json)
      rescue StandardError => error
        fix.reload.update!(verification: {'status' => 'unavailable', 'error_class' => error.class.name}) if phase && fix.reload.status == phase
      end
      private
      def with_target(page, target)
        if target['kind'] == 'metadata'
          page.with_lock do
            record = PageMetadata.find_or_initialize_by(site: @site, page: page)
            record.persisted? ? record.with_lock { yield record } : yield(record)
          end
        elsif target['kind'] == 'section'
          record = page.sections.find(target.fetch('section_id'))
          record.with_lock { yield record }
        else
          raise ArgumentError, 'This finding needs manual review in the CMS.'
        end
      end
      def values(record, target)
        target['kind'] == 'metadata' ? {'exists' => record.persisted?, 'title_tag' => record.title_tag, 'description' => record.description} : record.data.deep_dup
      end
      def write!(record, target, data)
        if target['kind'] == 'metadata'
          data['exists'] ? record.update!(data.slice('title_tag', 'description').merge(updated_by: @actor)) : record.destroy!
        else
          record.update!(data: data)
        end
      end
      def validate_value!(target, value)
        field = target['field']
        allowed = target['kind'] == 'metadata' ? %w[title_tag description] : target['kind'] == 'section' ? %w[image_alt cta_label cta_url] : []
        raise ArgumentError, 'This finding needs manual review in the CMS.' unless allowed.include?(field)
        maximum = {'title_tag' => 200, 'description' => 500, 'image_alt' => 300, 'cta_label' => 160, 'cta_url' => 1000}.fetch(field)
        raise ArgumentError, "Enter plain text from 1 to #{maximum} characters." unless value.is_a?(String) && value.strip.length.in?(1..maximum) && !value.include?("\0")
        if field == 'cta_url' && (LightekDesign::Catalog.safe_url(value) == '#' || value.start_with?('//'))
          raise ArgumentError, 'Choose a safe page URL, HTTPS URL, email or phone link.'
        end
      end
      def log(event, fix)
        Rails.logger.info({event: "lightek.growth.#{event}", site_id: @site.id, actor_id: @actor.id, fix_id: fix.id, finding_id: fix.finding_id, status: fix.status}.to_json)
      end
      def version!(fix, version)
        raise ActiveRecord::StaleObjectError.new(fix, 'update') unless version.to_s.match?(/\A\d+\z/) && fix.lock_version == version.to_i
      end
    end
  end
end
