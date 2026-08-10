class Profile < ApplicationRecord
  belongs_to :user
  include Visitable

  # Invoke your custom macro
  tracks_unique_visits
end
