# Serializes short admission decisions across all CPU hosts in this installation.
class StudioComputePool < ApplicationRecord
  validates :name, presence: true
end
