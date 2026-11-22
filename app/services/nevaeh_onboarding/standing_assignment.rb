# frozen_string_literal: true

require 'digest'

module NevaehOnboarding
  class StandingAssignment
    def self.paid_order(trial)
      order = trial.order
      return unless trial.activated_at? && trial.paid_access? && order&.paid_at? &&
        order.deleted_at.nil? && order.purpose == LightekAgency::Trial::ORDER_PURPOSE &&
        order.status.in?(%w[paid fulfilled]) && order.fulfillment_reference == "agency-trial-#{trial.id}" &&
        order.site_id == trial.billing_site_id && order.hosting_owner_id == trial.prospect_id &&
        trial.prospect.role == 'white_label' && trial.prospect.agency_id == trial.operator_id &&
        LightekPeople::LifecycleAccess.active?(trial.prospect) && operator?(trial.operator)

      order
    end

    def self.operator?(user)
      user&.role == 'super_admin' && LightekPeople::LifecycleAccess.active?(user)
    end

    def self.start!(trial)
      order = paid_order(trial)
      return unless order

      trial.operator.with_lock do
        NevaehOnboardingCase.find_or_create_by!(order: order) do |entry|
          entry.assign_attributes(trial: trial, operator: trial.operator, paid_at: order.paid_at)
          active = NevaehOnboardingPlaybook.find_by(operator: trial.operator, status: 'active')
          if active
            # Retain a concurrent comparison group for real-world rollback decisions.
            cohort = Digest::SHA256.hexdigest("agency-onboarding:#{order.id}").to_i(16).even? ? 'candidate' : 'control'
            entry.assign_attributes(playbook: active, evaluation_cohort: cohort)
          end
        end
      end
    end

    def self.record_dashboard!(prospect)
      trial = LightekAgency::Trial.find_by(prospect: prospect)
      return unless trial

      entry = start!(trial)
      entry&.with_lock { entry.update!(dashboard_at: Time.current) unless entry.closed_at? || entry.dashboard_at? }
    end

    def self.advance!(entry)
      entry.with_lock do
        next if entry.closed_at?
        trial = entry.trial
        unless paid_order(trial)&.id == entry.order_id
          entry.update!(closed_at: Time.current, blocker: 'eligibility_changed')
          next
        end

        prospect = trial.prospect
        mailbox = branded_mailbox(prospect)
        agency_ready = LightekPeople::LifecycleAccess.agency_ready?(prospect)
        if mailbox.nil? && entry.dashboard_at? && agency_ready
          provision_mailbox(entry, trial, prospect)
          mailbox = branded_mailbox(prospect)
        end
        if agency_ready && entry.dashboard_at? && mailbox&.sending_ready?
          entry.update!(mailbox_at: Time.current, completed_at: Time.current, closed_at: Time.current,
            blocker: nil, escalated_at: nil)
          next
        end

        reason = if !agency_ready
          'agency_access_review'
        elsif !entry.dashboard_at?
          'waiting_for_dashboard'
        elsif mailbox
          'mailbox_unavailable'
        elsif !email_verified?(trial, prospect)
          'email_verification_required'
        elsif entry.mailbox_attempts < 3
          'mailbox_retry_pending'
        else
          'mailbox_configuration'
        end
        elapsed = Time.current - entry.paid_at
        due = case reason
        when 'waiting_for_dashboard' then elapsed >= Improvement.escalation_hours(entry).hours
        when 'mailbox_retry_pending' then false
        else true
        end
        entry.escalated_at = nil if !due || entry.blocker != reason
        entry.escalated_at ||= Time.current if due
        entry.dashboard_escalated_at ||= entry.escalated_at if due && reason == 'waiting_for_dashboard'
        entry.blocker = reason
        if reason == 'waiting_for_dashboard' && elapsed >= 24.hours && !entry.followed_up_at?
          remind!(entry, prospect)
        end
        entry.save!
      end
    end

    def self.paid_trial(prospect)
      return unless prospect&.white_label? && LightekAgency::Trial.table_exists?

      trial = LightekAgency::Trial.find_by(prospect: prospect)
      trial if trial && paid_order(trial)
    end

    def self.email_verified?(trial, prospect)
      return false unless prospect.email_address == trial.order.customer_email

      LightekAgency::TrialRequest.where(site_id: trial.billing_site_id, operator_id: trial.operator_id,
        email_address: prospect.email_address).where('confirmed_at >= ?', trial.created_at - 1.day).exists?
    end

    def self.branded_mailbox(prospect)
      LightekMail::Account.mailboxes.joins(:domain).find_by(user: prospect, brand_member: true,
        lightek_mail_domains: {name: LightekEmailProvisioningService::DOMAIN})
    end

    def self.provision_mailbox(entry, trial, prospect)
      return if prospect.password_setup_required? || !email_verified?(trial, prospect)
      return if entry.mailbox_attempts >= 3 || entry.mailbox_attempted_at&.after?(15.minutes.ago)

      entry.mailbox_attempts += 1
      entry.mailbox_attempted_at = Time.current
      ApplicationRecord.transaction(requires_new: true) do
        LightekEmailProvisioningService.provision_for_paid_agency!(prospect, expected_email: prospect.email_address)
      end
    rescue LightekEmailProvisioningService::Unavailable, ActiveRecord::RecordInvalid
      # Keep the attempt and recheck verified mailbox state before any retry.
      nil
    end

    def self.remind!(entry, prospect)
      DymondDash::Notification.find_or_create_by!(recipient: prospect, subject: entry.order,
        category: 'system', title: 'Finish setting up your Lightek agency') do |notification|
        notification.body = 'Open the Agency Dashboard to finish setting up your paid membership and branded mailbox.'
        notification.url = Rails.application.routes.url_helpers.dashboard_agencies_path
      end
      entry.followed_up_at = Time.current
    end

    private_class_method :provision_mailbox, :remind!
  end
end
