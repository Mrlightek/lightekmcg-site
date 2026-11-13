module LightekCompliance
  class Monitor < ApplicationRecord
    self.table_name = 'lightek_compliance_monitors'
    STATES = %w[AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY].freeze
    belongs_to :employer, class_name: 'User'
    belongs_to :actor, class_name: 'User'
    validates :state, inclusion: {in: STATES}
    validates :provider, inclusion: {in: %w[openstates ny_openleg]}
    validates :query, presence: true, length: {maximum: 200}
    validate { errors.add(:provider,'New York statutes require New York jurisdiction') if provider == 'ny_openleg' && state != 'NY' }
  end
end
