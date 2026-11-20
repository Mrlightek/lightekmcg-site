module LightekAgency
  class TrialRequest < ApplicationRecord
    self.table_name = 'lightek_agency_trial_requests'

    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :operator, class_name: 'User'
    normalizes :email_address, with: ->(email) { email.strip.downcase }
    validates :first_name, :last_name, presence: true, length: {maximum: 100}
    validates :email_address, presence: true, length: {maximum: 254}, format: {with: URI::MailTo::EMAIL_REGEXP}

    generates_token_for :confirmation, expires_in: 24.hours do
      [site_id, operator_id, confirmed_at]
    end

    def available?
      Trial.public_operator(site)&.id == operator_id
    end

    def pending_confirmation? = confirmed_at.nil? && created_at >= 24.hours.ago

    def confirm!
      with_lock do
        raise Trial::Invalid, 'Request a new confirmation link.' unless pending_confirmation?

        site.with_lock do
          raise ActiveRecord::RecordNotFound unless available?

          prospect = User.find_by(email_address: email_address)
          trial = if prospect
            trial_for_existing_account(prospect)
          else
            Trial.invite!(operator: operator, billing_site: site,
              identity: {first_name: first_name, last_name: last_name, email_address: email_address},
              brand_name: 'My agency', duration_days: Trial::DEFAULT_DURATION_DAYS, skip_invitation: true)
          end
          update!(confirmed_at: Time.current)
          [trial, prospect.nil?]
        end
      end
    end

    private

    def trial_for_existing_account(prospect)
      prospect.with_lock do
        return unless prospect.access_active? && prospect.agency_id.in?([nil, operator_id])

        existing = Trial.find_by(prospect: prospect)
        return existing.operator_id == operator_id ? existing : nil if existing
        return unless prospect.role == 'client'
        return if Demo.where(client: prospect, created_client: true).exists?

        Trial.create!(prospect: prospect, operator: operator, billing_site: site,
          brand_name: 'My agency', expires_at: Trial::DEFAULT_DURATION_DAYS.days.from_now)
      end
    end
  end
end
