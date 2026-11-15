module LightekGrowth
  class Brief < ApplicationRecord
    self.table_name = 'lightek_growth_briefs'
    FIELDS = %w[offering audience customer_problem value_proposition voice goal goal_on].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :updated_by, class_name: 'User'
    validates :site_id, uniqueness: true
    validates :offering, :audience, :customer_problem, :value_proposition, :voice, :goal, length: {maximum: 2000}
    def complete? = %w[offering audience customer_problem value_proposition goal].all? { |field| public_send(field).present? }
  end
end
