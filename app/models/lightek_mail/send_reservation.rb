module LightekMail
  class SendReservation < ApplicationRecord
    self.table_name = "lightek_mail_send_reservations"
    belongs_to :account, class_name: "LightekMail::Account"
    belongs_to :user
  end
end
