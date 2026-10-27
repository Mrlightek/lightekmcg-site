module LightekMail
  class SendingPolicy < ApplicationRecord
    self.table_name = "lightek_mail_sending_policies"

    before_create :set_default_sending_enabled

    def self.synchronize
      policy = find_or_create_by!(id: 1) do |p|
        p.sending_enabled = true
      end
      policy.with_lock(requires_new: true) { yield policy }
    end

    def self.current
      find_or_create_by!(id: 1) do |p|
        p.sending_enabled = true
      end
    end

    private

    def set_default_sending_enabled
      self.sending_enabled = true if sending_enabled.nil?
    end
  end
end
