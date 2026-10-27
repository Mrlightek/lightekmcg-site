module LightekMail
  class SendingPolicy < ApplicationRecord
    class << self
      def synchronize(&block)
        @mutex ||= Mutex.new
        @mutex.synchronize(&block)
      end
    end
  end
end
