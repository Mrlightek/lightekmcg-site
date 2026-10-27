module LightekMail
  class SendingPolicy < ApplicationRecord
    self.table_name = "lightek_mail_sending_policies"

    def self.current
      find_or_create_by!(id: 1) do |p|
        p.sending_enabled = true
      end
    end
  end
end
