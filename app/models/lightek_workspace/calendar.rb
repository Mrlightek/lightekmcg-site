module LightekWorkspace
  class Calendar < ApplicationRecord
    self.table_name = 'lightek_shared_calendars'

    belongs_to :employer, class_name: 'User'
    has_many :events, class_name: 'LightekWorkspace::Event'
    validates :name, presence: true, length: {maximum: 120}
  end
end
