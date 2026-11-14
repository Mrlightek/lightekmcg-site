# frozen_string_literal: true
class NevaehIslamicSource < ApplicationRecord
  KINDS = %w[quran translation hadith commentary ethics].freeze
  belongs_to :creator, class_name: 'User'
  belongs_to :reviewer, class_name: 'User', optional: true
  has_many :passages, class_name: 'NevaehIslamicPassage', dependent: :restrict_with_error
  validates :name, :edition, :language, :source_url, :attribution, :license, :sha256, presence: true
  validates :name, :edition, :translator, :tradition, length: {maximum: 200}
  validates :kind, inclusion: {in: KINDS}
  validates :status, inclusion: {in: %w[draft reviewed]}
  validates :reviewer, :reviewed_at, presence: true, if: -> { status == 'reviewed' }
  validates :permission_evidence, presence: true, if: :training_permitted?
  validates :translator, presence: true, if: -> { kind == 'translation' }
  # A new edition is a new immutable import, keeping earlier dataset provenance valid.
  before_update do
    if (changes.keys - %w[status reviewer_id reviewed_at updated_at]).any?
      errors.add(:base, 'Import a new source edition to change text, attribution or permissions')
      throw :abort
    end
  end
end
