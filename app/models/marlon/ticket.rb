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

    validate :require_nevaeh_acceptance_for_closure

    before_validation :assign_number, on: :create
    before_validation :apply_category_defaults, on: :create

    after_create_commit :enqueue_nevaeh_backlog

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

    def require_nevaeh_acceptance_for_closure
      return unless will_save_change_to_status? && status == "resolved"
      fields = extra_fields.to_h
      return unless fields["nevaeh_knowledge_gap"] || fields.dig("nevaeh_work_order", "intent_key") == "ticket.structured.execute"
      disposition = fields.dig("nevaeh_backlog", "disposition")
      documented = disposition.is_a?(Hash) && %w[documented_obsolete documented_duplicate].include?(disposition["outcome"]) &&
        disposition["reason"].to_s.length >= 50 && disposition["actor_id"].present?
      unless fields.dig("nevaeh", "execution_status") == "verified" || documented
        errors.add(:status, "requires verified Nevaeh acceptance or a documented obsolete/duplicate disposition")
      end
    end

    def enqueue_nevaeh_backlog
      return if status == "resolved"
      return unless NevaehIntelligences::TicketBacklog.enabled?
      NevaehIntelligences::ProcessBacklogJob.perform_later(ticket_id: id)
    rescue StandardError => error
      # The recurring DB sweep recovers tickets committed during Redis outages.
      Rails.logger.error("Nevaeh intake enqueue failed ticket_id=#{id}: #{error.class}: #{error.message}")
    end

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
