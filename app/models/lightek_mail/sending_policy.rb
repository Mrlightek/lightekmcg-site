module LightekMail
  class SendingPolicy < ApplicationRecord
    self.table_name = "lightek_mail_sending_policies"

    def self.synchronize
      policy = create_or_find_by!(id: 1)
      policy.with_lock(requires_new: true) { yield policy }
    end
  end
end
