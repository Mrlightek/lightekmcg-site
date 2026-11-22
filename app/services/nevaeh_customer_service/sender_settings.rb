# frozen_string_literal: true

module NevaehCustomerService
  module SenderSettings
    class Invalid < StandardError; end
    STAFF_ROLES = %w[employee admin super_admin].freeze

    module_function

    def snapshot
      configuration(LightekMail::SendingPolicy.find_by(id: 1)&.nevaeh_support_sender.to_h)
    end

    def configuration(saved)
      return saved if saved.key?("mailbox_id")

      {"mailbox_id" => Integer(ENV["NEVAEH_SUPPORT_MAILBOX_ID"].to_s, 10, exception: false)}
    end

    def eligible_mailboxes(actor)
      authorize!(actor)
      LightekMail::Access.accounts(actor).joins(:user).where(users: {role: STAFF_ROLES})
        .includes(:user, :domain).order(:address).select { |account| ready?(account) }
    end

    def save!(actor:, mailbox_id:)
      authorize!(actor)
      selected = mailbox_id.presence
      if selected
        account = eligible_mailboxes(actor).find { |item| item.id.to_s == selected.to_s }
        raise Invalid, "Choose an available staff mailbox" unless account
      end

      LightekMail::SendingPolicy.synchronize do |policy|
        previous = configuration(policy.nevaeh_support_sender)
        history = Array(previous["previous_mailbox_ids"]) | [previous["mailbox_id"]].compact
        policy.update!(nevaeh_support_sender: {"mailbox_id" => account&.id,
          "previous_mailbox_ids" => history - [account&.id]})
      end
    end

    def ready?(account)
      account&.sending_ready? && LightekPeople::LifecycleAccess.active?(account.user) &&
        LightekMail::Access.accounts(account.user).exists?(account.id)
    rescue LightekMail::Access::Denied
      false
    end

    def authorize!(actor)
      unless actor&.role == "super_admin" && LightekPeople::LifecycleAccess.active?(actor)
        raise Invalid, "Platform administration access required"
      end
    end
  end
end
