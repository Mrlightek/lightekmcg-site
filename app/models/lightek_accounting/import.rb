module LightekAccounting
  class Import < ApplicationRecord
    self.table_name = 'lightek_accounting_imports'
    include AccountingSealedRecord
    belongs_to :book
    belongs_to :bank_account
    belongs_to :actor, class_name: 'User'
  end
end
