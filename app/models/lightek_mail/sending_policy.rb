module LightekMail
  class SendingPolicy
    class << self
      def synchronize(&block)
        @mutex ||= Mutex.new
        @mutex.synchronize(&block)
      end
    end
 < ApplicationRecord
    self.table_name = "lightek_mail_sending_policies"

    def self.current
      first || new(sending_enabled: true)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      new(sending_enabled: true)
    end
  end
end
