# frozen_string_literal: true

module LightekMail
  module MessageFolder
    NAMES = %w[inbox unread junk starred sent draft outbox archived all trash].freeze

    def self.scope(account, folder)
      messages = account.messages.where(trashed: folder == 'trash')
      case folder
      when 'inbox' then messages.where(direction: 'inbound', archived: false, junk: false)
      when 'unread' then messages.where(direction: 'inbound', archived: false, junk: false, read_at: nil)
      when 'junk' then messages.where(junk: true)
      when 'starred' then messages.where(starred: true)
      when 'archived' then messages.where(archived: true)
      when 'sent', 'draft' then messages.where(state: folder)
      when 'outbox' then messages.where(state: %w[queued submitting failed uncertain])
      else messages
      end
    end
  end
end
