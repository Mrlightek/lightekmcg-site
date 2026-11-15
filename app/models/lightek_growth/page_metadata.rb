module LightekGrowth
  class PageMetadata < ApplicationRecord
    self.table_name = 'lightek_growth_page_metadata'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :page, class_name: 'DymondSite::Page'
    belongs_to :updated_by, class_name: 'User'
    validates :page_id, uniqueness: true
    validates :title_tag, length: {maximum: 200}
    validates :description, length: {maximum: 500}
    validate { errors.add(:page, 'must belong to this website') if page && page.site_id != site_id }
  end
end
