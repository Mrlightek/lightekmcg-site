module LightekMarketing
  class PublicationSlotJob < ApplicationJob
    queue_as :default
    def perform(id)
      slot = PublicationSlot.find(id)
      PublicationCalendar.new(actor: slot.scheduled_by, site: slot.site).dispatch!(slot.id)
    end
  end
end
