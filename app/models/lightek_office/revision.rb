module LightekOffice
  class Revision < ApplicationRecord
    self.table_name = 'lightek_office_revisions'

    belongs_to :file, polymorphic: true
  end
end
