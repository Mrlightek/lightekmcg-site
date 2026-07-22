# frozen_string_literal: true
module Marlon
  class Ticket < ApplicationRecord
    self.table_name = "marlon_tickets"

    PRIORITIES = %w[low medium high critical].freeze
    STATUSES   = %w[open in_progress resolved].freeze

    belongs_to :submitted_by, class_name: "User", optional: true
    belongs_to :related, polymorphic: true, optional: true

    has_many :events, class_name: "Marlon::TicketEvent", dependent: :destroy, inverse_of: :ticket

    validates :title, presence: true
    validates :category, inclusion: { in: Marlon::TicketCategories.ids }
    validates :priority, inclusion: { in: PRIORITIES }
    validates :status,   inclusion: { in: STATUSES }
    validates :urgency, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }

    before_validation :assign_number, on: :create
    before_validation :apply_category_defaults, on: :create

    scope :open_first, -> { order(Arel.sql("CASE status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END"), :created_at) }
    scope :for_related, ->(record) { where(related: record) }

    def category_meta
      Marlon::TicketCategories.for(category)
    end

    def log!(action:, detail: nil, actor: nil)
      events.create!(action: action, detail: detail, actor: actor)
    end

    def resolve!(actor: nil)
      update!(status: "resolved", resolved_at: Time.current)
      log!(action: "Ticket resolved", actor: actor)
    end

    private

    def assign_number
      self.number ||= "LT-#{SecureRandom.random_number(9000) + 1000}"
    end

    def apply_category_defaults
      meta = category_meta
      return unless meta

      self.assigned_team ||= meta[:team]
      self.assigned_rep  ||= meta[:default_rep]
    end
  end
end
