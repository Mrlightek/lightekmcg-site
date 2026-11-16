module LightekGrowth
  class Step < ApplicationRecord
    self.table_name = 'lightek_growth_steps'
    DESTINATIONS = %w[brief intake tasks sales orders campaigns links website website_audit performance].freeze
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :plan, class_name: 'LightekGrowth::Plan'
    belongs_to :resolved_by, class_name: 'User', optional: true
    validates :key, presence: true, uniqueness: {scope: :plan_id}
    validates :position, numericality: {only_integer: true, in: 1..5}
    validates :status, inclusion: {in: %w[open completed dismissed]}
    validates :resolution_note, length: {maximum: 1000}
    validate do
      errors.add(:plan, 'must belong to this website') if plan && plan.site_id != site_id
      if !definition.is_a?(Hash) || definition.to_json.bytesize > 8000 || !DESTINATIONS.include?(definition['destination']) || !%w[navigate create_campaign].include?(definition['action'])
        errors.add(:definition, 'must use an installed growth action')
      end
      errors.add(:base, 'Recommendation evidence is immutable') if persisted? && (changes.keys & %w[site_id plan_id key position definition]).any?
      errors.add(:resolution_note, 'is required when resolving a recommendation') if status != 'open' && (resolution_note.blank? || resolved_by.nil? || resolved_at.nil?)
    end
  end
end
