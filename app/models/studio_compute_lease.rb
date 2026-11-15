class StudioComputeLease < ApplicationRecord
  belongs_to :studio_operation
  scope :active, -> { where(released_at: nil).where("expires_at > ?", Time.current) }
end
