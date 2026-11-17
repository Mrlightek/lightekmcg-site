module LightekPwa
  # Written only by the super-administrator platform setup service. A public
  # website manifest must never authorize use of central channel credentials.
  class PlatformOperator < ApplicationRecord
    self.table_name = 'lightek_pwa_platform_operators'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :operator, class_name: 'User'
    validates :site_id, uniqueness: true
  end
end
