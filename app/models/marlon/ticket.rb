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

    def confirm_customer_resolution!(actor:)
      with_lock do
        raise ArgumentError, "Choose your own technical support ticket" unless customer_resolution_allowed?(actor)
        unless status == "resolved"
          log!(action: "Customer confirmed resolution", actor: actor)
          resolve!(actor: actor)
        end
      end
      self
    end

    def customer_resolution_allowed?(actor)
      fields = extra_fields.to_h
      actor&.persisted? && submitted_by_id == actor.id && related_type.blank? &&
        [nil, "support_hub"].include?(fields["source"]) && category.in?(%w[technical deployment]) &&
        fields["nevaeh_work_order"].blank? && fields.dig("nevaeh", "execution_status").blank?
    end

    def reply_as_support!(actor:, detail:)
      raise ArgumentError, "Enter a reply between 1 and 8,000 characters" unless detail.is_a?(String) && detail.strip.length.between?(1, 8_000)

      with_lock do
        raise ArgumentError, "Choose an open customer support ticket" unless submitted_by_id && status != "resolved"

        event = log!(action: "#{actor.full_name} replied", detail: detail.strip, actor: actor)
        update!(status: "in_progress") if status == "open"
        event
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
