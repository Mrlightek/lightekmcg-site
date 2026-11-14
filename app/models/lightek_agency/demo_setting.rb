module LightekAgency
  class DemoSetting < ApplicationRecord
    self.table_name = 'lightek_agency_demo_settings'
    belongs_to :agency, class_name: 'User'
    belongs_to :public_site, class_name: 'DymondSite::Site', optional: true
    belongs_to :upgrade_product, class_name: 'LightekCommerce::Product', optional: true
    validates :agency_id, uniqueness: true
    validates :duration_days, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 90}
    validates :max_active, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 100}
    validate do
      errors.add(:agency, 'must be an agency or platform operator') unless agency&.role.in?(%w[white_label super_admin])
      errors.add(:public_site, 'must belong to this agency') if public_site && public_site.tenant != agency
      errors.add(:public_site, 'is required for public requests') if public_enabled? && !public_site
      if upgrade_product && !Demos.upgrade_products(agency).exists?(id: upgrade_product_id)
        errors.add(:upgrade_product, 'must be an available installation sold by this agency or the platform')
      end
    end
  end
end
