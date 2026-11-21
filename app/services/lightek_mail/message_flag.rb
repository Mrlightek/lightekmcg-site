# frozen_string_literal: true

module LightekMail
  module MessageFlag
    NAMES = %w[archived trashed starred unread junk].freeze

    def self.update!(message, flag:, value:)
      raise ArgumentError, 'Choose archive, trash, star, unread or junk.' unless NAMES.include?(flag)

      attributes = case flag
      when 'unread' then {read_at: nil}
      when 'junk' then {junk: value, archived: false, trashed: false}
      else {flag => value}
      end
      message.update!(attributes)
    end
  end
end
