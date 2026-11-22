# frozen_string_literal: true

module LightekExperiments
  class Experiment < ApplicationRecord
    self.table_name = 'lightek_experiments'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :created_by, class_name: 'User'
    has_many :assignments, class_name: 'LightekExperiments::Assignment', dependent: :restrict_with_error

    validates :name, :control, :challenger, presence: true, length: { maximum: 160 }
    validates :surface, inclusion: { in: ->(_) { Surfaces::RULES.keys } }
    validates :winner, inclusion: { in: %w[control challenger] }, allow_nil: true
    validate do
      errors.add(:challenger, 'must differ from the control') if control == challenger
    end

    attr_readonly :site_id, :created_by_id, :name, :surface, :target, :control, :challenger

    def copy_for(arm)
      arm == 'challenger' ? challenger : control
    end
  end
end
