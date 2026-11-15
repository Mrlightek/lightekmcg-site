# frozen_string_literal: true
module LightekSales
  class Opportunity < ApplicationRecord
    self.table_name = 'lightek_sales_opportunities'
    include SalesSiteRecord
    STAGES = {'discovery' => 10, 'qualified' => 30, 'proposal' => 60, 'negotiation' => 80, 'closed_won' => 100, 'closed_lost' => 0}.freeze
    CURRENCIES = %w[USD CAD EUR GBP AUD].freeze
    GUIDANCE = {
      'discovery' => 'Ask what they need, what is difficult today, and what a successful result looks like.',
      'qualified' => 'Confirm budget, decision maker and timing. Agree on the next meeting.',
      'proposal' => 'Send a clear scope, price and delivery date. Schedule a proposal review.',
      'negotiation' => 'Resolve open questions and confirm who will approve the agreement.',
      'closed_won' => 'Arrange the order, payment and delivery through Commerce. Check that onboarding has an owner.',
      'closed_lost' => 'Record why the deal was lost and what you learned for the next opportunity.'
    }.freeze
    belongs_to :account, class_name: 'LightekSales::Account'
    belongs_to :contact, class_name: 'LightekMarketing::Contact', optional: true
    validates :name, presence: true, length: {maximum: 160}
    validates :stage, inclusion: {in: STAGES.keys}
    validates :forecast_category, inclusion: {in: %w[pipeline best_case commit omitted]}
    validates :currency, inclusion: {in: CURRENCIES}
    validates :amount_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 9_000_000_000_000_000}
    validates :probability, numericality: {only_integer: true, in: 0..100}
    validates :close_on, presence: true
    validates :next_step, :loss_reason, length: {maximum: 300}
    validates :notes, length: {maximum: 20_000}
    validates :loss_reason, presence: true, if: -> { stage == 'closed_lost' }
    validate do
      same_sales_site(:account)
      same_sales_site(:contact)
      if contact && contact.sales_account_id != account_id
        errors.add(:contact, 'must belong to the selected company')
      end
    end
    before_validation do
      self.name = name.to_s.strip
      self.next_step = next_step.to_s.strip.presence
      self.loss_reason = loss_reason.to_s.strip.presence
      self.currency = currency.to_s.upcase
      if stage_changed?
        self.stage_changed_at = Time.current
        self.probability = STAGES.fetch(stage, 0) unless probability_changed?
        self.closed_at = closed? ? Time.current : nil
      end
      self.probability = STAGES[stage] if closed?
    end
    scope :open_pipeline, -> { where(stage: %w[discovery qualified proposal negotiation]) }
    def amount = format("%.2f", amount_cents.to_i / 100.0)
    def closed? = stage.in?(%w[closed_won closed_lost])
    def guidance = GUIDANCE.fetch(stage, 'Choose a supported stage to see guidance for the next conversation.')
    def weighted_cents = Rational(amount_cents * probability, 100).round
  end
end
