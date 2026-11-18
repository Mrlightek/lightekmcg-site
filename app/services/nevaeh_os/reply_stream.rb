# frozen_string_literal: true

module NevaehOs
  module ReplyStream
    module_function

    def valid_key?(key)
      key.is_a?(String) && key.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
    end

    def name(user_id,key) = "nevaeh_reply:#{user_id}:#{key}"

    def publisher(actor,key)
      return unless valid_key?(key)
      channel=name(actor.id,key)
      available=true
      lambda do |text|
        next unless available
        begin
          ActionCable.server.broadcast(channel,{text:text})
        rescue StandardError => error
          available=false
          Rails.logger.warn("Nevaeh reply stream unavailable (#{error.class})")
        end
      end
    end
  end
end
