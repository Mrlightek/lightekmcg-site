# frozen_string_literal: true
module LightekSales
  class IntakeSweepJob < ApplicationJob
    queue_as :default
    def perform
      IntakeRule.where(enabled: true).where.not(enabled_at: nil).find_each do |rule|
        captured = IntakeEntry.where(site_id: rule.site_id, origin: 'website').where.not(inquiry_id: nil).select(:inquiry_id)
        WebsiteTemplateInquiry.where(site_id: rule.site_id, template_key: rule.template_key, section_key: rule.section_key)
          .where('created_at >= ?', rule.enabled_at).where.not(id: captured).order(:id).limit(100).pluck(:id).each do |id|
            IntakeJob.perform_later(id)
          end
        # Pending entries recover a failed queue dispatch or an interrupted job.
        IntakeEntry.where(site_id: rule.site_id, origin: 'website', status: 'awaiting_review')
          .where.not(inquiry_id: nil).where(inquiry_id: WebsiteTemplateInquiry.where(site_id: rule.site_id, template_key: rule.template_key, section_key: rule.section_key).where('created_at >= ?', rule.enabled_at))
          .order(:id).limit(100).pluck(:inquiry_id).each { |id| IntakeJob.perform_later(id) }
      end
    end
  end
end
