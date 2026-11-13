module LightekAccounting
  class Reconciliation < ApplicationRecord
    self.table_name = 'lightek_accounting_reconciliations'
    include AccountingSealedRecord
    belongs_to :book
    belongs_to :bank_account
    belongs_to :actor, class_name: 'User'
    validates :status, inclusion: {in: %w[draft final superseded]}
    validate do
      errors.add(:bank_account,'belongs to another book') unless bank_account.book_id == book_id
      if persisted? && %w[final superseded].include?(attribute_in_database('status'))
        if %w[book_id bank_account_id actor_id starts_on ends_on sealed_data].any? { |field| will_save_change_to_attribute?(field) }
          errors.add(:base,'Finalized reconciliation proofs are immutable')
        end
        errors.add(:status,'a superseded proof cannot be reused') if attribute_in_database('status') == 'superseded' && status != 'superseded'
      end
      if status == 'final' && (data['cleared_difference_cents'] != 0 || data['book_difference_cents'] != 0)
        errors.add(:base,'Both reconciliation proofs must balance')
      end
    end
  end
end
