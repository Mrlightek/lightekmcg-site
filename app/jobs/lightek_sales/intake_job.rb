# frozen_string_literal: true
module LightekSales
  class IntakeJob < ApplicationJob
    queue_as :default
    retry_on ActiveRecord::Deadlocked, ActiveRecord::StaleObjectError, wait: 5.seconds, attempts: 3
    def perform(inquiry_id)
      inquiry = WebsiteTemplateInquiry.find_by(id: inquiry_id)
      return unless inquiry
      rule = IntakeRule.find_by(site_id: inquiry.site_id, template_key: inquiry.template_key, section_key: inquiry.section_key, enabled: true)
      return unless rule && rule.enabled_at && inquiry.created_at >= rule.enabled_at
      actor = inquiry.site.tenant if inquiry.site.tenant_type == 'User'
      return unless actor
      entry, reservations, accepted = nil, [], false
      begin
        intake = Intake.new(actor: actor, site: inquiry.site)
        entry = intake.capture!(inquiry.id, rule: rule)
        return if entry.processed? || entry.status == 'needs_review'
        LightekAgency::PackagePolicy.authorize!(actor, 'commerce')
        # Reserve outside the sales transaction so a rollback and explicit
        # release cannot decrement an unrelated, already-counted write.
        reservations = LightekAgency::PackagePolicy.reserve_write!(user: actor, feature: 'commerce')
        inquiry.site.with_lock do
          rule.reload
          return unless rule.enabled? && inquiry.created_at >= rule.enabled_at
          entry.reload
          return if entry.processed? || entry.status == 'needs_review'
          intake.process!(entry.id, lock_version: entry.lock_version)
        end
        accepted = true
      rescue ActiveRecord::RecordInvalid, ArgumentError, LightekAgency::PackagePolicy::Denied => error
        # The original request remains durable; only safe, bounded review
        # messages are recorded. No customer mail or subscription is created.
        if entry
          inquiry.site.with_lock do
            entry.reload
            entry.update!(status: 'needs_review', error_message: error.message.first(300)) unless entry.processed?
          end
        end
      ensure
        LightekAgency::PackagePolicy.release_write!(reservations) unless accepted
      end
    end
  end
end
