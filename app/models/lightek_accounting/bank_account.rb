module LightekAccounting
  class BankAccount < ApplicationRecord
    self.table_name = 'lightek_accounting_bank_accounts'
    include AccountingSealedRecord
    belongs_to :book
    has_many :transactions, dependent: :restrict_with_exception
    has_many :reconciliations, dependent: :restrict_with_exception
    validates :name, :opening_on, presence: true
    validate do
      if persisted? && (will_save_change_to_sealed_data? || will_save_change_to_opening_on?) && transactions.exists?
        errors.add(:base,'Opening balances are immutable once transactions exist; use reviewed correcting entries')
      end
      Money.integer!(data.fetch('opening_cents'))
    rescue ArgumentError, KeyError
      errors.add(:base,'Opening balance is required in integer cents')
    end
  end
end
