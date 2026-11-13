module LightekAccounting
  class Rule < ApplicationRecord
    self.table_name = 'lightek_accounting_rules'
    include AccountingSealedRecord
    belongs_to :book
    belongs_to :category
  end
end
