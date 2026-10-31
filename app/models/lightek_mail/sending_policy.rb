module LightekMail
  class SendingPolicy < ApplicationRecord
    self.table_name = "lightek_mail_sending_policies"

    def self.current
      create_or_find_by!(id: 1)
    end

    def self.sending_enabled? = current.sending_enabled?

    # Database locking serializes mail reservations across Passenger and workers.
    # Always yield the persisted policy; a process-local mutex cannot do this.
    def self.synchronize
      policy = current
      policy.with_lock(requires_new: true) { yield policy }
    end
  end
end
