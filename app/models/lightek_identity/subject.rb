module LightekIdentity
  class Subject < ApplicationRecord
    self.table_name = 'lightek_identity_subjects'
    belongs_to :connection
    belongs_to :user, optional: false
  end
end
