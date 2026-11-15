# frozen_string_literal: true
module LightekSales
  class Task < ApplicationRecord
    self.table_name = 'lightek_sales_tasks'
    include SalesSiteRecord
    RECORD_TYPES = %w[LightekSales::Lead LightekSales::Opportunity LightekSales::Account LightekMarketing::Contact].freeze
    belongs_to :created_by, class_name: 'User'
    belongs_to :completed_by, class_name: 'User', optional: true
    belongs_to :record, polymorphic: true
    validates :owner, :title, :due_at, :source_key, presence: true
    validates :title, length: {maximum: 300}
    validates :source_key, length: {maximum: 160}, uniqueness: {scope: :site_id}
    validates :record_type, inclusion: {in: RECORD_TYPES}
    validates :status, inclusion: {in: %w[open completed canceled]}
    validate { same_sales_site(:record) }
    scope :open_tasks, -> { where(status: 'open') }
    scope :due, -> { open_tasks.where('due_at <= ?', Time.current) }
    private def sales_owner_has_site_access
      super if new_record? || owner_id_changed?
    end
    def record_kind
      {'LightekSales::Lead' => 'lead', 'LightekSales::Opportunity' => 'opportunity', 'LightekSales::Account' => 'account', 'LightekMarketing::Contact' => 'contact'}.fetch(record_type)
    end
  end
end
