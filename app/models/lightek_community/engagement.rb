# frozen_string_literal: true
module LightekCommunity
  class Engagement < ApplicationRecord
    self.table_name = "lightek_community_engagements"
    belongs_to :post
    belongs_to :profile
    validates :kind, inclusion: { in: %w[like save rsvp] }
    validates :profile_id, uniqueness: { scope: %i[post_id kind] }
  end
end
