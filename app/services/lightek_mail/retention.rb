module LightekMail
  module Retention
    BUSY_STATES = %w[queued submitting].freeze
    module_function

    def remove!(account:, message_id:, actor:)
      account.with_lock do
        message = account.messages.find(message_id)
        unless message.trashed? && !message.state.in?(BUSY_STATES)
          raise ArgumentError, "Move a completed message or draft to Trash before deleting it."
        end

        preserved = account.messages.discoverable.exists?(message.id) && protected?(account, message.discovery_date)
        if preserved
          RetainedMessage.preserve!(message)
          DiscoveryEvent.create!(employer_id: account.user_id, account: account, actor: actor, action: "deleted_mail_preserved", result_count: 1, details: {message_id: message.id})
        end
        message.destroy!
        preserved
      end
    end

    def protected?(account, timestamp, now: Time.current)
      return true if MatterHold.active.exists?(account_id: account.id)

      rule = RetentionRule.find_by(account_id: account.id)
      rule && timestamp > rule.cutoff(now)
    end

    def expire!(now: Time.current)
      accounts = Account.where(id: RetainedMessage.select(:account_id))
      accounts.where.not(id: MatterHold.active.select(:account_id)).find_each do |account|
        account.with_lock do
          next if MatterHold.active.exists?(account_id: account.id)

          records = RetainedMessage.where(account: account)
          rule = RetentionRule.find_by(account_id: account.id)
          records = records.where(sent_or_received_at: ..rule.cutoff(now)) if rule
          count = 0
          records.limit(100).each do |record|
            record.destroy!
            count += 1
          end
          if count.positive?
            DiscoveryEvent.create!(employer_id: account.user_id, account: account,
              action: "retained_mail_expired", result_count: count)
          end
        end
      end
    end
  end
end
