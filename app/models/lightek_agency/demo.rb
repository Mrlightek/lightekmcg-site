module LightekAgency
  class Demo < ApplicationRecord
    self.table_name = 'lightek_agency_demos'
    belongs_to :agency, class_name: 'User'
    belongs_to :client, class_name: 'User', optional: true
    belongs_to :site, class_name: 'DymondSite::Site', optional: true
    belongs_to :demo_request, class_name: 'LightekAgency::DemoRequest', optional: true
    belongs_to :upgrade_order, class_name: 'LightekCommerce::Order', optional: true
    before_validation(on: :create) { self.public_id ||= SecureRandom.uuid }
    validates :public_id, uniqueness: true
    validates :name, presence: true, length: {maximum: 150}
    validates :status, inclusion: {in: %w[active upgrading converted expired cleaned]}
    validates :expires_at, presence: true
    scope :available, -> { where(status: %w[active upgrading], cleaned_at: nil).where('expires_at > ?', Time.current) }
    def active? = cleaned_at.nil? && status.in?(%w[active upgrading]) && expires_at > Time.current
    def to_param = public_id
  end
end
