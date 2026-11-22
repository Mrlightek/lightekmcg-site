# frozen_string_literal: true

module NevaehOs
  module MailActions
    INPUTS = {
      'mail.mailbox.list' => {},
      'mail.mailbox.status' => {'mailbox_id'=>:id},
      'mail.mailbox.receiving.check' => {'mailbox_id'=>:id},
      'mail.message.search' => {'mailbox_id'=>:id, 'folder'=>16, 'query'=>:mail_query},
      'mail.message.open' => {'mailbox_id'=>:id, 'message_id'=>:id},
      'mail.message.flag' => {'mailbox_id'=>:id, 'message_id'=>:id, 'flag'=>10, 'value'=>:boolean},
      'mail.draft.create' => {'mailbox_id'=>:id, 'to'=>512, 'subject'=>200, 'text'=>:mail_body},
      'mail.draft.send' => {'mailbox_id'=>:id, 'message_id'=>:id, 'confirmed'=>:confirmation}
    }.transform_values(&:freeze).freeze

    module_function

    def authorize!(actor, intent, values)
      accounts = LightekMail::Access.accounts(actor)
      return accounts if intent == 'mail.mailbox.list'

      account = accounts.find(values.fetch('mailbox_id'))
      return account unless values.key?('message_id')

      account.messages.find(values.fetch('message_id'))
    rescue LightekMail::Access::Denied => error
      raise ArgumentError, error.message
    end

    def perform!(intent, target, values, action_id:)
      case intent
      when 'mail.mailbox.list'
        SpecialistTasks.summary(target, %w[id address display_name enabled])
      when 'mail.mailbox.status'
        {'mailbox_id'=>target.id, 'enabled'=>target.enabled?, 'sending_ready'=>target.sending_ready?}
      when 'mail.mailbox.receiving.check'
        result = LightekMail::ReceivingStatus.check(target)
        {'mailbox_id'=>target.id, 'mx_ready'=>result.fetch(:ok), 'text'=>result.fetch(:message)}
      when 'mail.message.search'
        folder = values.fetch('folder')
        raise ArgumentError, 'Choose a valid mail folder.' unless LightekMail::MessageFolder::NAMES.include?(folder)

        messages = LightekMail::MessageFolder.scope(target, folder)
        matches = LightekMail::Search.apply(messages, values.fetch('query'))
        {'mailbox_id'=>target.id, 'folder'=>folder, 'count'=>matches.count,
         'records'=>matches.order(created_at: :desc, id: :desc).limit(30).map { |message| message_summary(message) }}
      when 'mail.message.open'
        message_summary(target).merge('links'=>[{'label'=>'Open message in Mail Studio', 'url'=>message_path(target)}])
      when 'mail.message.flag'
        LightekMail::MessageFlag.update!(target, flag: values.fetch('flag'), value: values.fetch('value'))
        message_summary(target)
      when 'mail.draft.create'
        attributes = LightekMail::ComposeMessage.attributes(account: target, attributes: values.slice('to', 'subject', 'text'))
        message = LightekMail::Submission.create!(account: target, attributes: attributes, draft: true, idempotency_key: "nevaeh-action-#{action_id}")
        message_summary(message).merge('links'=>[{'label'=>'Review draft', 'url'=>message_path(message)}])
      when 'mail.draft.send'
        LightekMail::Submission.send_draft!(target.account, target)
        message_summary(target.reload).merge('text'=>'Draft queued for delivery. Check Mail Studio for its delivery status.')
      end
    end

    def message_summary(message)
      message.attributes.slice('id', 'account_id', 'subject', 'from_address', 'direction', 'state', 'created_at',
                               'archived', 'trashed', 'starred', 'junk', 'read_at')
    end

    def message_path(message)
      "/dashboard/mail/accounts/#{message.account_id}/messages/#{message.id}"
    end
  end
end
