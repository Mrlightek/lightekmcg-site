module LightekMail
  class CustomerSuspension < ApplicationRecord
    self.table_name = "lightek_mail_customer_suspensions"
    belongs_to :user
  end
end
