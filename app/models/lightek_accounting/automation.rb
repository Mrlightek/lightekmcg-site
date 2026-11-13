module LightekAccounting
  class Automation < ApplicationRecord
    self.table_name = 'lightek_accounting_automations'
    include AccountingSealedRecord
    belongs_to :book
    belongs_to :actor, class_name: 'User'
  end
end
