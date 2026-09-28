class Production < ApplicationRecord
  KINDS = %w[general film series episode commercial social live event].freeze
  STATUSES = %w[development preproduction production postproduction approved published archived].freeze

  belongs_to :studio_project
  has_many :studio_scenes, dependent: :nullify
  has_many :studio_operations, dependent: :nullify
  has_many :studio_publications, dependent: :nullify
  has_many :studio_live_operations, dependent: :nullify

  validates :name, presence: true, length: { maximum: 160 }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
end
