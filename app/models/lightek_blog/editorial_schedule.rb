# frozen_string_literal: true

module LightekBlog
  class EditorialSchedule < ApplicationRecord
    self.table_name = 'lightek_blog_editorial_schedules'

    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :actor, class_name: 'User'
    belongs_to :last_goal, class_name: 'NevaehGoal', optional: true
  end
end
