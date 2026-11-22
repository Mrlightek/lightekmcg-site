module LightekGrowth
  class FeatureClip < ApplicationRecord
    self.table_name = 'lightek_growth_feature_clips'
    belongs_to :feature_showcase, class_name: 'LightekGrowth::FeatureShowcase'
    has_one_attached :file
    has_many_attached :screenshots
    validates :title, presence: true, length: {maximum: 80}
    validates :body, presence: true, length: {maximum: 280}
    validates :position, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than: 6}
    validate { errors.add(:base, 'Retain the rendered feature source; prepare a new kit to revise it') if persisted? && (changes.keys & %w[feature_showcase_id position feature_key category title body]).any? }
    def ready? = file.attached? && checksum.present? && checksum == file.blob.checksum && file.blob.byte_size.positive? && file.blob.service.exist?(file.blob.key)
  end
end
