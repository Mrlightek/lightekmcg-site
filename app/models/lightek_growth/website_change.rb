# frozen_string_literal: true

module LightekGrowth
  class WebsiteChange < ApplicationRecord
    self.table_name = 'lightek_growth_website_changes'
    attr_readonly :site_id, :action_id, :actor_id, :operation, :previous_source, :result
  end
end
