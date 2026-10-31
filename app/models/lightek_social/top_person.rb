# frozen_string_literal: true
module LightekSocial
  class TopPerson < ApplicationRecord
    self.table_name = "lightek_social_top_people"
    belongs_to :profile
    belongs_to :person, class_name: "Profile"
    validates :position, inclusion: { in: 1..8 }
    validates :person_id, uniqueness: { scope: :profile_id }
  end
end
