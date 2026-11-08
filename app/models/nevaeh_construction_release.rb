# frozen_string_literal: true
class NevaehConstructionRelease < ApplicationRecord
  belongs_to :nevaeh_construction
  validates :version, uniqueness: {scope: :nevaeh_construction_id}
  validates :status, inclusion: {in: %w[built verified failed active retired]}
  # Released inputs and source artifacts are immutable. Status/evidence may advance.
  before_update do
    if %w[version definition sample_tests artifacts fingerprint nevaeh_construction_id].any? { |field| will_save_change_to_attribute?(field) }
      errors.add(:base, 'Build a new release to change an implementation')
      throw :abort
    end
  end
end
