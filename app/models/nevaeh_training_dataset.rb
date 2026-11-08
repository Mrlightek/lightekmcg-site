# frozen_string_literal: true
class NevaehTrainingDataset < ApplicationRecord
  belongs_to :creator, class_name: 'User'
  validates :name, presence: true, length: {maximum: 160}
  validates :status, inclusion: {in: %w[draft approved]}
  validate :valid_examples
  before_update do
    self.status = 'draft' if will_save_change_to_examples? || will_save_change_to_provenance?
  end
  private
  def valid_examples
    rows = examples
    valid = rows.is_a?(Array) && rows.length.between?(5, 512) && rows.all? do |row|
      row.is_a?(Hash) && row.keys.sort == %w[prompt response] && row.values.all? { |text| text.is_a?(String) && text.strip.length.between?(1, 2000) }
    end
    errors.add(:examples, 'need 5–512 prompt/response pairs, each under 2000 characters') unless valid
    errors.add(:examples, 'exceed the 256 KB dataset budget') if JSON.generate(rows).bytesize > 262144
  end
end
