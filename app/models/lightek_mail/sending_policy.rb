# frozen_string_literal: true

module LightekMail
  class SendingPolicy < ApplicationRecord
    self.table_name = "lightek_mail_sending_policies"

    # Reservations, global stops and queued delivery share the same persisted
    # policy lock across processes. Always yield the actual policy to callers.
    def self.synchronize
      policy = create_or_find_by!(id: 1)
      policy.with_lock(requires_new: true) { yield policy }
    end

    def self.current
      find_by(id: 1) || new(sending_enabled: false)
    end

    def self.sending_enabled?
      current.sending_enabled?
    end
  end
end
