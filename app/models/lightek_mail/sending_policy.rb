module LightekMail
  class SendingPolicy < ApplicationRecord
    class << self
      def synchronize(&block)
        @mutex ||= Mutex.new
        @mutex.synchronize(&block)
      end

      def current
        first || new
      end
    end
  end
end
