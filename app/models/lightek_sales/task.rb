# frozen_string_literal: true
module LightekSales
  class Task < ApplicationRecord
    self.table_name = 'lightek_sales_tasks'
    include SalesSiteRecord
    RECORD_KINDS = {'LightekSales::Lead' => 'lead', 'LightekSales::Opportunity' => 'opportunity',
      'LightekSales::Account' => 'account', 'LightekMarketing::Contact' => 'contact',
      'LightekSales::SocialProspect' => 'prospect'}.freeze
    RECORD_TYPES = RECORD_KINDS.keys.freeze
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

    def self.visible_in_sales(site)
      tasks = where(site: site)
      LightekSales::Access.prospecting_allowed?(site) ? tasks : tasks.where.not(record_type: 'LightekSales::SocialProspect')
    end

    def self.in_queue_order
      reply_priority = <<~SQL.squish
        CASE WHEN lightek_sales_tasks.status = 'open' AND lightek_sales_tasks.record_type = 'LightekSales::SocialProspect'
          AND (SELECT activity.body FROM lightek_sales_activities activity
               WHERE activity.site_id = lightek_sales_tasks.site_id
                 AND activity.record_type = lightek_sales_tasks.record_type
                 AND activity.record_id = lightek_sales_tasks.record_id AND activity.kind = 'outreach'
               ORDER BY activity.created_at DESC, activity.id DESC LIMIT 1) LIKE 'Reply received%'
        THEN 1 ELSE 0 END
      SQL
      select('lightek_sales_tasks.*', Arel.sql("#{reply_priority} AS prospect_reply_priority"))
        .order(Arel.sql('prospect_reply_priority DESC'), :due_at, :id)
    end

    def reply_priority? = has_attribute?(:prospect_reply_priority) && self[:prospect_reply_priority] == 1

    private def sales_owner_has_site_access
      super if new_record? || owner_id_changed?
    end
    def record_kind = RECORD_KINDS.fetch(record_type)
  end
end
