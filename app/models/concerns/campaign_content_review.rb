require 'digest'
require 'json'
module CampaignContentReview
  extend ActiveSupport::Concern
  CONTENT_FIELDS = %w[channel production_format headline message cta_label cta_url media_url mail_account_id recipient_email].freeze
  included do
    belongs_to :content_approved_by, class_name: 'User', optional: true
    before_validation do
      if has_attribute?(:content_review_required) && content_review_required? && approved_content_digest != content_digest
        self.approved_content_digest = nil
        self.content_approved_by_id = nil
        self.content_approved_at = nil
        self.status = 'draft' if status == 'ready'
      end
    end
  end
  def content_digest
    Digest::SHA256.hexdigest(JSON.generate(CONTENT_FIELDS.to_h { |field| [field, has_attribute?(field) ? self[field] : nil] }))
  end
  def content_approved?
    return true unless has_attribute?(:content_review_required) && content_review_required?
    approved_content_digest == content_digest && content_approved_by_id.present? && content_approved_at.present?
  end
end
