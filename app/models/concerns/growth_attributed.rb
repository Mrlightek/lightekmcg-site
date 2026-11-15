# Attribution is set by trusted capture/conversion code, never CRM form input.
module GrowthAttributed
  extend ActiveSupport::Concern
  included do
    belongs_to :growth_visit, class_name: 'LightekGrowth::Visit', optional: true
    after_create_commit do
      if growth_attribution
        Rails.logger.info({event: 'lightek.growth.attributed', site_id: site_id, record_type: self.class.name, record_id: id, visit_id: growth_visit_id}.to_json)
      end
    end
    validate do
      if has_attribute?(:growth_visit_id)
        if growth_visit && !LightekGrowth::Visit.where(id: growth_visit.id, site_id: site_id).exists?
          errors.add(:growth_visit, 'must be a recorded visit for this website')
        end
        errors.add(:growth_visit, 'cannot replace recorded attribution') if persisted? && growth_visit_id_changed?
      end
    end
  end
  def growth_attribution = has_attribute?(:growth_visit_id) ? growth_visit : nil
end
