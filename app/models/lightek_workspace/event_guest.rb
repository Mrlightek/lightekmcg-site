module LightekWorkspace
  class EventGuest < ApplicationRecord
    self.table_name = 'lightek_shared_event_guests'

    belongs_to :event, class_name: 'LightekWorkspace::Event'
    belongs_to :user
    validates :response, inclusion: {in: %w[pending accepted tentative declined]}
  end
end
