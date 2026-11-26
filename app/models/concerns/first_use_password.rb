module FirstUsePassword
  extend ActiveSupport::Concern

  SETUP_TOKEN_PREFIX = 'setup-v2-'.freeze
  SETUP_TOKEN_PURPOSE = 'lightek-account-setup-v2'.freeze
  included do
    attr_accessor :skip_password_setup_invitation
    attr_reader :password_setup_invitation_error
    # Accept setup links issued before configurable lifetimes were introduced.
    generates_token_for :password_setup, expires_in: 20.minutes do
      [password_salt.last(10), password_setup_required?]
    end
    after_create_commit :invite_first_use_account
  end

  class_methods do
    def find_for_password_setup!(token)
      user = if token.start_with?(SETUP_TOKEN_PREFIX)
        id, password_salt_suffix = generated_token_verifier.verify(
          token.delete_prefix(SETUP_TOKEN_PREFIX), purpose: SETUP_TOKEN_PURPOSE
        )
        candidate = find_by(id: id)
        candidate if candidate&.password_salt&.last(10) == password_salt_suffix
      else
        find_by_token_for(:password_setup, token)
      end

      raise ActiveSupport::MessageVerifier::InvalidSignature unless user&.password_setup_required?

      user
    end
  end

  def password_setup_token(link_minutes: AccountSetupSetting.link_minutes)
    token = self.class.generated_token_verifier.generate(
      [id, password_salt.last(10)], purpose: SETUP_TOKEN_PURPOSE, expires_in: link_minutes.minutes
    )
    "#{SETUP_TOKEN_PREFIX}#{token}"
  end

  def send_password_setup_invitation!
    raise ArgumentError, 'This account already has a chosen password' unless password_setup_required?
    PasswordsMailer.reset(self).deliver_later
  end

  private
  def invite_first_use_account
    # Deployed owners get the verified installation handoff from the control
    # plane, after installation. Do not send an invitation during remote bootstrap.
    return unless password_setup_required? && !skip_password_setup_invitation
    send_password_setup_invitation!
  rescue StandardError => error
    @password_setup_invitation_error = true
    Rails.logger.error("[Account setup] invitation enqueue failed user=#{id} #{error.class}")
  end
end
