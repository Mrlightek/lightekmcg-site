# frozen_string_literal: true

class SusuCycle < ApplicationRecord
  STATUSES = %w[draft active completed cancelled].freeze

  belongs_to :susu_group
  has_many :susu_rounds, dependent: :destroy

  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :number, uniqueness: { scope: :susu_group_id }

  def current_round
    susu_rounds.where(status: %w[open funding processing funded]).order(:number).first
  end
end
