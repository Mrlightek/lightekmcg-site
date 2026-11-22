# frozen_string_literal: true

class NevaehCalendarInvitee < ApplicationRecord
  belongs_to :agenda_item, class_name: 'NevaehAgendaItem'
  belongs_to :mailbox, class_name: 'LightekMail::Account'
  belongs_to :message, class_name: 'LightekMail::Message', optional: true
end
