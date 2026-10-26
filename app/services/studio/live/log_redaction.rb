# frozen_string_literal: true
require "delegate"
module Studio
  module Live
    module LogRedaction
      class SafeLogger < SimpleDelegator
        %i[debug info warn error fatal unknown].each do |level|
          define_method(level) do |message = nil, &block|
            text = message || block&.call
            text = "[Studio live transport details redacted]" if text.to_s.include?("live_chunk") || text.to_s.include?("StudioBroadcastChannel")
            __getobj__.public_send(level, text)
          end
        end
      end
      def logger
        @studio_live_logger ||= SafeLogger.new(super)
      end
    end
  end
end
