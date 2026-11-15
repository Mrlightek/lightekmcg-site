module LightekSales
  class Quote < ApplicationRecord
    self.table_name = 'lightek_sales_quotes'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :opportunity
    belongs_to :accepted_by, class_name: 'User', optional: true
    belongs_to :created_by, class_name: 'User'
    belongs_to :order, class_name: 'LightekCommerce::Order', optional: true
    validates :status, inclusion: {in: %w[draft issued superseded accepted declined]}
    validates :title, presence: true, length: {maximum: 160}
    validates :portal_host, presence: true, length: {maximum: 253}, format: {with: /\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/}
    validates :customer_email, presence: true, format: {with: URI::MailTo::EMAIL_REGEXP}, length: {maximum: 254}
    validates :currency, inclusion: {in: ['USD']}
    validates :expires_on, :series_key, presence: true
    validates :total_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 9_000_000_000_000_000}
    validates :terms, length: {maximum: 20_000}
    validates :acceptance_channel, inclusion: {in: %w[staff customer_portal]}, if: -> { status == 'accepted' }
    validates :accepted_name, presence: true, if: -> { status == 'accepted' }
    validates :accepted_name, length: {maximum: 160}
    validates :acceptance_reference, length: {maximum: 300}
    validate do
      errors.add(:opportunity, 'must belong to this website') if opportunity && opportunity.site_id != site_id
      errors.add(:order, 'must belong to this website') if order && order.site_id != site_id
      if persisted? && status_was != 'draft' && %w[lines total_cents portal_host customer_email title currency terms expires_on opportunity_id series_key revision].any? { |field| will_save_change_to_attribute?(field) }
        errors.add(:base, 'Issued quote details are immutable; create a revision')
      end
      valid_lines = lines.is_a?(Array) && lines.size.in?(1..50) && lines.all? { |line| line.is_a?(Hash) && line['product_id'].is_a?(Integer) && line['quantity'].is_a?(Integer) && line['quantity'].in?(1..100) && line['unit_price_cents'].is_a?(Integer) && line['unit_price_cents'] >= 0 }
      errors.add(:lines, 'must contain catalog items and valid quantities') unless valid_lines
      errors.add(:total_cents, 'must match the saved items') if valid_lines && total_cents != lines.sum { |line| line['quantity'] * line['unit_price_cents'] }
    end
  end
end
