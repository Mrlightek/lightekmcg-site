class NilClass
  def sending_enabled?
    true
  end
end

module LightekMail
  class SendingPolicy < ApplicationRecord
    class << self
      def synchronize(&block)
        @mutex ||= Mutex.new
        @mutex.synchronize(&block)
      end

      def current
        first || new(active: true)
      end

      def sending_enabled?
        current.sending_enabled?
      end
    end

    def sending_enabled?
      respond_to?(:active?) ? active? : true
    end
  end
end
