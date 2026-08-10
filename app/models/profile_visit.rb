class ProfileVisit < ApplicationRecord
  belongs_to :user
  belongs_to :profile
end
