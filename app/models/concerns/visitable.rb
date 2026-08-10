# app/models/concerns/visitable.rb
module Visitable
  extend ActiveSupport::Concern

  class_methods do
    def tracks_unique_visits
      # 1. Dynamically associate the profile with its visits
      has_many :profile_visits, dependent: :destroy

      # 2. Define a method to safely record a unique visit
      define_method(:record_visit_from) do |visitor|
        # Do not count if the profile owner views their own profile
        return if user_id == visitor.id 

        # find_or_create_by ensures the visitor is logged exactly once
        profile_visits.find_or_create_by(user: visitor)
      end

      # 3. Define a quick helper to grab the total unique count
      define_method(:unique_visits_count) do
        profile_visits.count
      end
    end
  end
end
