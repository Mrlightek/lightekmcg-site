# frozen_string_literal: true
require 'digest'
class NevaehStudyRoutine < ApplicationRecord
  SLOTS = %w[fajr dhuhr asr maghrib isha tahajjud].freeze
  SETTINGS = %w[source_id language_model_id daily_times dataset_ids training_enabled auto_activate window_minutes passages_per_session training_epochs].freeze
  belongs_to :creator, class_name: 'User'
  belongs_to :source, class_name: 'NevaehIslamicSource'
  belongs_to :language_model, class_name: 'NevaehLanguageModel', optional: true
  has_many :sessions, class_name: 'NevaehStudySession', dependent: :restrict_with_error
  validates :name, presence: true, length: {maximum: 160}
  validates :window_minutes, numericality: {only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 60}
  validates :passages_per_session, numericality: {only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 50}
  validates :training_epochs, numericality: {only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 50}
  validate :valid_schedule
  validate :valid_learning_inputs
  before_update do
    self.reading_after_id = 0 if will_save_change_to_source_id?
    self.training_cursor = 0 if will_save_change_to_dataset_ids? || will_save_change_to_source_id?
  end
  def settings_fingerprint
    Digest::SHA256.hexdigest(NevaehIntelligences::CanonicalJson.dump(attributes.slice(*SETTINGS).merge('server_zone' => NevaehIntelligences::Islamic::StudyClock.zone.name)))
  end
  private
  def valid_schedule
    valid = daily_times.is_a?(Hash) && daily_times.keys.sort == SLOTS.sort && daily_times.values.all? { |value| value.is_a?(String) && value.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/) }
    errors.add(:daily_times, 'must contain a distinct HH:MM server time for each of the six periods') unless valid && daily_times.values.uniq.length == 6
  end
  def valid_learning_inputs
    errors.add(:source, 'must be a reviewed Quran edition') unless source&.kind == 'quran' && source.status == 'reviewed'
    return unless training_enabled?
    errors.add(:source, 'needs recorded neural training permission') unless source&.training_permitted?
    errors.add(:language_model, 'must be enabled for scheduled training') unless language_model&.enabled?
    valid_ids = dataset_ids.is_a?(Array) && dataset_ids.length.between?(1, 1000) && dataset_ids.all? { |id| id.is_a?(Integer) && id.positive? } && dataset_ids.uniq == dataset_ids
    unless valid_ids
      errors.add(:dataset_ids, 'must select approved training batches')
      return
    end
    datasets = NevaehTrainingDataset.where(id: dataset_ids).to_a
    unless datasets.length == dataset_ids.length && datasets.all? { |dataset| dataset.status == 'approved' && dataset.provenance['source'] == 'islamic_library' && dataset.provenance['source_id'].to_i == source_id }
      errors.add(:dataset_ids, 'must all be approved batches from the selected Quran source')
    end
  end
end
