module LightekAccounting
  class Workbook < ApplicationRecord
    self.table_name = 'lightek_accounting_workbooks'
    include AccountingSealedRecord
    belongs_to :book
    belongs_to :actor, class_name: 'User'
  end
end
