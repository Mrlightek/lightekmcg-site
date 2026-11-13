module LightekAccounting
  class Transaction < ApplicationRecord
    self.table_name = 'lightek_accounting_transactions'
    include AccountingSealedRecord
    belongs_to :book
    belongs_to :bank_account
    belongs_to :category, optional: true
    belongs_to :statement_import, class_name: 'LightekAccounting::Import', optional: true
    belongs_to :reconciliation, optional: true
    validates :posted_on, :source_key, presence: true
    validates :source_key, uniqueness: {scope: :bank_account_id}
    validate do
      errors.add(:bank_account,'belongs to another book') unless bank_account.book_id == book_id
      errors.add(:category,'belongs to another book') if category && category.book_id != book_id
      errors.add(:posted_on,'precedes the opening balance') if posted_on && posted_on < bank_account.opening_on
      if new_record? && posted_on && bank_account.reconciliations.where(status: 'final').where('ends_on >= ?',posted_on).exists?
        errors.add(:posted_on,'is in a finalized period; reopen it before adding records')
      end
      Money.integer!(data.fetch('amount_cents'))
      if persisted? && (will_save_change_to_sealed_data? || will_save_change_to_bank_account_id? || will_save_change_to_book_id? || will_save_change_to_posted_on? || will_save_change_to_source_key?)
        errors.add(:base,'Posted financial amounts and source are immutable; add a correcting entry')
      end
    rescue ArgumentError, KeyError
      errors.add(:base,'Amount must be integer cents')
    end
    def amount_cents = data.fetch('amount_cents')
  end
end
