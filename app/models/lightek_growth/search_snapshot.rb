module LightekGrowth
  class SearchSnapshot < ApplicationRecord
    self.table_name = 'lightek_growth_search_snapshots'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :created_by, class_name: 'User'
    attr_readonly :site_id, :created_by_id, :property, :starts_on, :ends_on, :rows, :inspection

    def review_candidate
      rows.select { |row| row.fetch('impressions') >= 100 && row.fetch('ctr') < 0.02 }
        .max_by { |row| row.fetch('impressions') }
    end
  end
end
