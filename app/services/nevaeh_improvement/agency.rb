# frozen_string_literal: true

module NevaehImprovement
  module Agency
    KEY = 'agency_onboarding'
    MAIL_PREFIX = 'agency_onboarding_'
    STRATEGIES = {'email_24h' => 24, 'email_48h' => 48}.freeze

    module_function

    def strategies = STRATEGIES.keys
    def available_for?(operator) = sender(operator).present?
    def negative_examples
      [{}, {'purchase_email_matches' => false, 'waiting_for_dashboard' => true},
        {'purchase_email_matches' => true, 'waiting_for_dashboard' => false}]
    end

    def action(strategy, signals)
      return unless STRATEGIES.key?(strategy) && signals['waiting_for_dashboard'] && signals['purchase_email_matches']

      'send_follow_up'
    end

    def accepts?(action, signals)
      action.nil? || (action == 'send_follow_up' && signals.values_at('waiting_for_dashboard', 'purchase_email_matches') == [true, true])
    end

    def action_regression?(row, strategy)
      # A safety regression blocks any version that would repeat the action.
      row.outcome['regression'] ||
        (strategy == 'email_24h' && row.receipt['resolved_before_48h'] == true)
    end

    def update!(entry)
      cycle = Cycle.new(entry.operator, KEY)
      row = NevaehResolutionObservation.find_by(workflow: KEY, subject_id: entry.id)
      if !row && entry.blocker == 'waiting_for_dashboard' && entry.paid_at <= 24.hours.ago
        row = cycle.observe!(entry.id, {
          'waiting_for_dashboard' => true,
          'purchase_email_matches' => entry.order.customer_email == entry.trial.prospect.email_address
        })
      end
      return unless row && row.operator_id == entry.operator_id

      row.with_lock do
        next if row.measured_at?

        receipt = row.receipt.dup
        strategy = cycle.strategy(row)
        if (hours = STRATEGIES[strategy]) && action(strategy, row.signals) &&
            row.started_at > Cycle::WINDOW.ago && entry.paid_at <= hours.hours.ago && current_case?(entry)
          submit!(row, receipt, entry)
        end

        if (message_id = receipt['message_id'])
          message = LightekMail::Message.find_by(id: message_id)
          receipt['mail_status'] = message&.state || 'unavailable'
          if message&.state == 'queued' && message.updated_at < 15.minutes.ago &&
              current_message?(message) && (receipt['requeued_at'].nil? || Time.iso8601(receipt['requeued_at']) < 15.minutes.ago)
            LightekMail::DeliverJob.perform_later(message.id)
            receipt['requeued_at'] = Time.current.iso8601
          end
        end
        if entry.dashboard_at?
          receipt['resolved_before_48h'] = entry.dashboard_at < entry.paid_at + 48.hours
        end
        receipt['mailbox_attempts'] = entry.mailbox_attempts
        receipt['mailbox_ready_at'] = entry.mailbox_at.iso8601 if entry.mailbox_at?
        row.receipt = receipt
        if row.started_at <= Cycle::WINDOW.ago
          within_window = entry.completed_at && entry.completed_at <= row.started_at + Cycle::WINDOW
          row.assign_attributes(measured_at: Time.current, outcome: {'verified' => !!within_window,
            'handoff' => !within_window && entry.escalated_at?, 'regression' => duplicate_submission?(row)})
        end
        row.save! if row.changed?
      end
    end

    def current_message?(message)
      parts = /\A#{MAIL_PREFIX}([0-9]+)\z/.match(message.idempotency_key.to_s)
      return false unless parts

      row = NevaehResolutionObservation.find_by(id: parts[1], workflow: KEY, measured_at: nil)
      return false unless row && row.started_at > Cycle::WINDOW.ago && row.receipt['message_id'] == message.id &&
        NevaehOnboarding::StandingAssignment.operator?(row.operator)

      entry = NevaehOnboardingCase.find_by(id: row.subject_id, operator: row.operator)
      return false unless entry && current_case?(entry) &&
        action(Cycle.new(row.operator, KEY).strategy(row), row.signals)

      message.to_addresses == [entry.trial.prospect.email_address] && sender(row.operator)&.id == message.account_id
    end

    def current_case?(entry)
      !entry.closed_at? && !entry.dashboard_at? && entry.blocker == 'waiting_for_dashboard' &&
        NevaehOnboarding::StandingAssignment.paid_order(entry.trial)&.id == entry.order_id &&
        entry.trial.prospect.email_address == entry.order.customer_email &&
        LightekPeople::LifecycleAccess.agency_ready?(entry.trial.prospect)
    end

    def sender(operator)
      if defined?(NevaehCustomerService::Outbound)
        mailbox = NevaehCustomerService::Outbound.mailbox
      else
        id = Integer(ENV['NEVAEH_SUPPORT_MAILBOX_ID'].to_s, 10, exception: false)
        mailbox = LightekMail::Account.mailboxes.find_by(id: id) if id
      end
      mailbox if mailbox&.sending_ready? && mailbox.user.role.in?(%w[employee admin super_admin]) &&
        LightekPeople::LifecycleAccess.active?(mailbox.user) && LightekMail::Access.accounts(operator).exists?(mailbox.id)
    rescue LightekMail::Access::Denied
      nil
    end

    def submit!(row, receipt, entry)
      return if receipt['message_id']

      mailbox = sender(row.operator)
      unless mailbox
        receipt['mail_status'] = 'no_sender'
        return
      end

      key = "#{MAIL_PREFIX}#{row.id}"
      message = LightekMail::Message.find_by(idempotency_key: key)
      message ||= LightekMail::Submission.create!(account: mailbox, idempotency_key: key, attributes: {
        'to' => entry.trial.prospect.email_address, 'subject' => 'Finish setting up your Lightek agency',
        'text' => 'Sign in to Lightek and open Clients & Agencies to finish setting up your paid membership and branded mailbox.'
      })
      receipt['message_id'] = message.id
    rescue LightekMail::Submission::Unavailable, LightekMail::Access::Denied
      receipt['mail_status'] = 'submission_blocked'
    end

    def duplicate_submission?(row)
      LightekMail::Message.where(idempotency_key: "#{MAIL_PREFIX}#{row.id}", state: %w[submitting sent uncertain]).count > 1
    end
  end
end
