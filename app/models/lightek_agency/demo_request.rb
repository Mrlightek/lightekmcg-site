module LightekAgency
  class DemoRequest < ApplicationRecord
    self.table_name = 'lightek_agency_demo_requests'
    belongs_to :agency, class_name: 'User'
    belongs_to :growth_visit, class_name: 'LightekGrowth::Visit', optional: true
    attr_readonly :growth_visit_id
    validate do
      if growth_visit && growth_visit.site.tenant != agency
        errors.add(:growth_visit, 'must belong to this agency')
      end
    end
    has_one :demo, class_name: 'LightekAgency::Demo', dependent: :restrict_with_exception
    before_validation(on: :create) { self.nonce ||= SecureRandom.hex(32); self.expires_at ||= 24.hours.from_now }
    validates :email_address, presence: true, format: {with: URI::MailTo::EMAIL_REGEXP}
    validates :first_name, :last_name, presence: true, length: {maximum: 100}
    validates :status, inclusion: {in: %w[pending activated]}
    generates_token_for :confirmation, expires_in: 24.hours do
      [nonce, status, email_address, agency_id]
    end
  end
end
