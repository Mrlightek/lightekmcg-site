class NevaehWorkspace < ApplicationRecord
  belongs_to :user
  validates :user_id,uniqueness:true
  validate do
    errors.add(:panels,'must contain at most eight work handles') unless panels.is_a?(Array) && panels.size<=8 && panels.to_json.bytesize<=8000
  end
end
